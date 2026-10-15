import { withFreshUrls } from "../files/attachmentUrls.js";
import { randomUUID } from "node:crypto";
import { Router } from "express";
import { z } from "zod";
import { db, Prisma, tx } from "../db/prisma.js";
import type { Conversation } from "../generated/prisma/client.js";
import { AppError } from "../util/errors.js";
import { fallbackTitle, generateTitle } from "../conversations/title.js";
import { takeAi } from "../auth/limits.js";
import { mergeBriefing, type MergeChat } from "../conversations/merge.js";
import { conversationIdsFor, deleteConversations } from "../conversations/delete.js";
import { userOf } from "../auth/context.js";
import { scheduleIndex } from "../recall/index.js";
import { searchConversations } from "../conversations/search.js";
import { userCrypto, type UserCrypto } from "../crypto/userData.js";
import { CONV, openConversationText, openMessage, sealConversation, sealMessage } from "../conversations/codec.js";

export const conversationsRouter = Router();

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const citationSchema = z
  .object({
    id: z.string(),
    kind: z.enum(["kb", "web", "file", "conversation"]),
    title: z.string(),
    url: z.string(),
    snippet: z.string().default(""),
    site: z.string().default(""),
    sourceType: z.string().optional(),
  })
  .passthrough();

const imageSchema = z
  .object({ url: z.string(), sourceUrl: z.string().default(""), title: z.string().default(""), site: z.string().default("") })
  .passthrough();

const evidenceSchema = z
  .object({ tag: z.string(), claim: z.string().max(1000), quote: z.string().max(1000), score: z.number().min(0).max(1) })
  .passthrough();

const attachmentSchema = z
  .object({
    id: z.string(),
    name: z.string(),
    mime: z.string().default(""),
    size: z.number().default(0),
    kind: z.enum(["image", "document", "video", "audio"]),
    status: z.string().default("ready"),
    error: z.string().nullish(),
    meta: z.record(z.string(), z.unknown()).default({}),
    createdAt: z.string().optional(),
  })
  .passthrough()
  .transform(({ url: _u, thumbUrl: _t, ...rest }: Record<string, unknown>) => rest);

// Round Table transcript on an assistant message (shape owned by the app; capped).
const tableSchema = z
  .object({
    seats: z.array(z.record(z.string(), z.unknown())).max(6).default([]),
    reviews: z.array(z.record(z.string(), z.unknown())).max(6).default([]),
    unresolved: z.array(z.string().max(500)).max(12).default([]),
  })
  .passthrough()
  .refine((t) => JSON.stringify(t).length <= 60_000, "table transcript too large");

const messageSchema = z.object({
  role: z.enum(["user", "assistant", "context"]),
  content: z.string(),
  model: z.string().nullish(),
  meta: z.record(z.string(), z.unknown()).default({}),
  citations: z.array(citationSchema).max(50).default([]),
  usedIds: z.array(z.string()).max(50).default([]),
  images: z.array(imageSchema).max(12).default([]),
  evidence: z.array(evidenceSchema).max(200).default([]),
  attachments: z.array(attachmentSchema).max(10).default([]),
  isError: z.boolean().default(false),
  table: tableSchema.nullish(),
});

// `origin` names where a new chat came from ("assistant": the assistant overlay); only set when the chat is created.
export const putSchema = z.object({ messages: z.array(messageSchema).min(1).max(2000), origin: z.enum(["assistant"]).optional().catch(undefined) });
const patchSchema = z
  .object({
    title: z.string().trim().min(1).max(120).optional(),
    pinned: z.boolean().optional(),
    archived: z.boolean().optional(),
  })
  .refine((b) => b.title !== undefined || b.pinned !== undefined || b.archived !== undefined, "Nothing to change");

function idParam(raw: string): string {
  if (!UUID_RE.test(raw)) throw new AppError(404, "not_found", "Conversation not found");
  return raw.toLowerCase();
}

/** A conversation row plus its fork parent's title (loaded with WITH_PARENT). */
type Row = Conversation & { parent?: { title: string | null } | null };

// Every read of a summary also loads the fork parent's title (one query, no N+1).
const WITH_PARENT = { parent: { select: { title: true } } } satisfies Prisma.ConversationInclude;

/** For rows written without the include (upsert): fetch the parent's title separately. */
async function withParent(r: Conversation): Promise<Row> {
  if (!r.forkedFrom) return r;
  const parent = await db().conversation.findUnique({ where: { id: r.forkedFrom }, select: { title: true } });
  return { ...r, parent };
}

/** A conversation row with its sealed text (title, preview, fork parent's title) decrypted; legacy plaintext passes through. */
const openRow = (c: UserCrypto, r: Row): Row => ({ ...openConversationText(c, r), ...(r.parent ? { parent: openConversationText(c, r.parent) } : {}) });

const summary = (r: Row) => ({
  id: r.id,
  title: r.title,
  titleSource: r.titleSource,
  messageCount: r.messageCount,
  preview: r.preview,
  pinned: r.pinnedAt != null,
  archived: r.archivedAt != null,
  origin: r.origin ?? null,
  forkedFrom: r.forkedFrom ?? null,
  forkPoint: r.forkPoint ?? null,
  parent: r.forkedFrom ? { id: r.forkedFrom, title: r.parent?.title ?? null } : null,
  mergedFrom: r.mergedFrom ?? [],
  createdAt: r.createdAt.toISOString(),
  updatedAt: r.updatedAt.toISOString(),
});

/** JSON column input (validated request data). */
const asJson = (v: unknown) => v as Prisma.InputJsonValue;

// GET /conversations?q=&limit=&before=<ISO updatedAt>&archived=1
// Pinned chats come first; archived ones are listed only with archived=1.
// Every query is limited to the caller's chats (`userId: uid`, which is
// `user_id IS NULL` for the not-yet-claimed rows); another user's chat reads as not found.
conversationsRouter.get("/", async (req, res) => {
  db();
  const uid = userOf(req).id;
  const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 100);
  const q = typeof req.query.q === "string" ? req.query.q.trim().slice(0, 100) : "";
  const archived = req.query.archived === "1" || req.query.archived === "true";
  const before = typeof req.query.before === "string" && !Number.isNaN(Date.parse(req.query.before)) ? new Date(req.query.before) : null;
  const crypto = await userCrypto(uid);
  if (q) {
    // Titles and messages are encrypted, so search runs in the app on decrypted text of the caller's chats
    // (src/conversations/search.ts): stemmed + typo-tolerant, each item carries the matched excerpt.
    const hits = await searchConversations({ uid, q, archived, before, limit, crypto });
    const ids = hits.map((h) => h.id);
    const found = await db().conversation.findMany({ where: { id: { in: ids }, userId: uid }, include: WITH_PARENT });
    const byId = new Map(found.map((r) => [r.id, r]));
    const items = hits.flatMap(({ id, snippet: sn }) => {
      const r = byId.get(id);
      if (!r) return [];
      return [{ ...summary(openRow(crypto, r)), snippet: sn ? sn.text : null, snippetMatch: sn ? { start: sn.start, length: sn.length } : null }];
    });
    res.json({ conversations: items });
    return;
  }
  const rows = await db().conversation.findMany({
    where: {
      userId: uid,
      archivedAt: archived ? { not: null } : null,
      ...(before ? { updatedAt: { lt: before } } : {}),
    },
    // Pinned first (most recently pinned on top), then by activity.
    orderBy: [{ pinnedAt: { sort: "desc", nulls: "last" } }, { updatedAt: "desc" }],
    take: limit,
    include: WITH_PARENT,
  });
  res.json({ conversations: rows.map((r) => summary(openRow(crypto, r))) });
});

/** A conversation with its messages, as GET /:id returns it; null when it does not exist. */
async function loadConversation(id: string, uid: string | null) {
  const row = await db().conversation.findFirst({
    where: { id, userId: uid },
    include: {
      ...WITH_PARENT,
      messages: {
        orderBy: { position: "asc" },
        select: { role: true, content: true, model: true, citations: true, usedIds: true, isError: true, images: true, evidence: true, attachments: true, meta: true, table: true },
      },
    },
  });
  if (!row) return null;
  const c = await userCrypto(uid);
  return {
    ...summary(openRow(c, row)),
    messages: row.messages.map((raw) => openMessage(c, raw)).map((m) => ({
      role: m.role,
      content: m.content,
      model: m.model,
      citations: m.citations,
      usedIds: m.usedIds,
      isError: m.isError,
      images: m.images,
      evidence: m.evidence,
      // Stored as the app sent it (validated attachment objects); links are signed again at read time.
      attachments: withFreshUrls(m.attachments),
      meta: m.meta ?? {},
      table: m.table ?? null,
    })),
  };
}

const FORK_SUFFIX = " · fork";
const forkSchema = z.object({ at: z.number().int().min(1) });
const mergeSchema = z.object({ ids: z.array(z.string()).length(2) });

// POST /conversations/merge {ids:[a,b]}: a NEW chat that starts from an AI
// briefing of both; the originals are untouched.
conversationsRouter.post("/merge", async (req, res) => {
  db();
  const { ids } = mergeSchema.parse(req.body);
  const [a, b] = ids.map(idParam);
  const uid = userOf(req).id;
  if (a === b) throw new AppError(400, "same_conversation", "Pick two different chats to merge");
  const chats: MergeChat[] = [];
  for (const id of [a, b]) {
    const conv = await loadConversation(id, uid);
    if (!conv) throw new AppError(404, "not_found", "Conversation not found");
    if (conv.messages.length === 0) throw new AppError(400, "empty", "A chat to merge has no messages");
    chats.push({ id, title: conv.title || conv.preview || "Untitled chat", messages: conv.messages });
  }
  const [chatA, chatB] = chats;
  const briefing = await mergeBriefing(chatA, chatB);
  const title = `${chatA.title.slice(0, 56)} + ${chatB.title.slice(0, 56)}`;
  const preview = `Merged: ${chatA.title} + ${chatB.title}`.slice(0, 140);
  const meta = {
    sources: chats.map((c) => ({ id: c.id, title: c.title, messageCount: c.messages.length })),
    summarySource: briefing.source,
  };
  // One nested create: the chat and its briefing message are written atomically.
  const c = await userCrypto(uid);
  const text = sealConversation(c, { title, preview });
  const first = sealMessage(c, { content: briefing.text, citations: [], images: [], evidence: [], meta, table: undefined });
  const created = await db().conversation.create({
    data: {
      id: randomUUID(),
      title: text.title,
      titleSource: "derived",
      messageCount: 1,
      preview: text.preview,
      origin: "merge",
      mergedFrom: [a, b],
      userId: uid,
      messages: { create: { position: 0, role: "context", content: first.content, meta: asJson(first.meta) } },
    },
    select: { id: true },
  });
  res.status(201).json(await loadConversation(created.id, uid));
});

/** Most chats one bulk delete names by id. */
export const BULK_DELETE_MAX = 500;
export const bulkDeleteSchema = z.union([
  z.object({ ids: z.array(z.string().regex(UUID_RE, "Invalid chat id")).min(1).max(BULK_DELETE_MAX) }).strict(),
  z
    .object({
      all: z.literal(true),
      includeArchived: z.boolean().default(true),
      includePinned: z.boolean().default(true),
      archivedOnly: z.boolean().default(false),
    })
    .strict(),
]);

// POST /conversations/bulk-delete {ids} | {all: true, includeArchived?, includePinned?, archivedOnly?}
// Deletes the caller's chats (others' ids are ignored) exactly like DELETE /:id, files included.
conversationsRouter.post("/bulk-delete", async (req, res) => {
  db();
  const body = bulkDeleteSchema.parse(req.body);
  const uid = userOf(req).id;
  const ids =
    "ids" in body
      ? body.ids.map((i) => i.toLowerCase())
      : await conversationIdsFor(uid, { includeArchived: body.includeArchived, includePinned: body.includePinned, archivedOnly: body.archivedOnly });
  res.json({ deleted: await deleteConversations(ids, uid) });
});

// POST /conversations/:id/fork {at}: a copy of the first `at` saved messages.
conversationsRouter.post("/:id/fork", async (req, res) => {
  db();
  const id = idParam(req.params.id);
  const { at } = forkSchema.parse(req.body);
  const uid = userOf(req).id;
  const crypto = await userCrypto(uid);
  const newId = await tx(async (c) => {
    // Raw: Prisma has no SELECT ... FOR UPDATE; the lock keeps the parent stable while copying.
    await c.$queryRaw`SELECT 1 FROM conversations WHERE id = ${id}::uuid AND user_id IS NOT DISTINCT FROM ${uid}::uuid FOR UPDATE`;
    const parent = await c.conversation.findFirst({ where: { id, userId: uid }, select: { title: true, preview: true } });
    if (!parent) throw new AppError(404, "not_found", "Conversation not found");
    const count = await c.conversationMessage.count({ where: { conversationId: id } });
    if (at > count) throw new AppError(400, "bad_request", "That message isn't in this chat anymore.");
    const open = openConversationText(crypto, parent);
    const base = (open.title || open.preview || "Untitled chat").replace(/ · fork$/, "");
    const created = await c.conversation.create({
      data: {
        id: randomUUID(),
        title: crypto.seal(CONV, "title", `${base.slice(0, 120 - FORK_SUFFIX.length)}${FORK_SUFFIX}`),
        titleSource: "derived",
        messageCount: at,
        preview: parent.preview, // already sealed (or legacy plaintext): copied as is, same owner
        origin: "fork",
        forkedFrom: id,
        forkPoint: at,
        userId: uid,
      },
      select: { id: true },
    });
    // Every message field is copied as stored (sealed values stay valid: same owner, AAD has no row id), so fields added to the model later come along too.
    const prefix = await c.conversationMessage.findMany({ where: { conversationId: id, position: { lt: at } }, orderBy: { position: "asc" } });
    await c.conversationMessage.createMany({
      data: prefix.map(({ conversationId: _from, ...m }) => ({
        ...m,
        conversationId: created.id,
        citations: asJson(m.citations),
        images: asJson(m.images),
        evidence: asJson(m.evidence),
        attachments: asJson(m.attachments),
        meta: asJson(m.meta),
        table: m.table === null ? Prisma.DbNull : asJson(m.table),
      })),
    });
    return created.id;
  });
  res.status(201).json(await loadConversation(newId, uid));
});

conversationsRouter.get("/:id", async (req, res) => {
  db();
  const conv = await loadConversation(idParam(req.params.id), userOf(req).id);
  if (!conv) throw new AppError(404, "not_found", "Conversation not found");
  res.json(conv);
});

// Full replace of the conversation; the app is the source of truth.
conversationsRouter.put("/:id", async (req, res) => {
  db();
  const id = idParam(req.params.id);
  const { messages, origin } = putSchema.parse(req.body);
  const uid = userOf(req).id;
  const firstUser = messages.find((m) => m.role === "user")?.content ?? "";
  const preview = firstUser.replace(/\s+/g, " ").trim().slice(0, 140);
  const crypto = await userCrypto(uid);
  const sealedPreview = preview ? crypto.seal(CONV, "preview", preview) : null;

  const saved = await tx(async (c) => {
    // Another user's id: nothing is written (and it reads as not found).
    const owner = await c.conversation.findUnique({ where: { id }, select: { userId: true } });
    if (owner && owner.userId !== uid) throw new AppError(404, "not_found", "Conversation not found");
    // A plain upsert by primary key runs as INSERT ... ON CONFLICT, so concurrent first saves do not collide.
    const row = await c.conversation.upsert({
      where: { id },
      create: { id, messageCount: messages.length, preview: sealedPreview, userId: uid, ...(origin ? { origin } : {}) },
      update: { messageCount: messages.length, ...(sealedPreview ? { preview: sealedPreview } : {}), updatedAt: new Date() },
    });
    if (row.userId !== uid) throw new AppError(404, "not_found", "Conversation not found");
    await c.conversationMessage.deleteMany({ where: { conversationId: id } });
    await c.conversationMessage.createMany({
      data: messages.map((m, position) => {
        const s = sealMessage(crypto, { content: m.content, citations: m.citations, images: m.images, evidence: m.evidence, meta: m.meta ?? {}, table: m.table });
        return {
          conversationId: id,
          position,
          role: m.role,
          content: s.content,
          model: m.model ?? null,
          citations: asJson(s.citations),
          usedIds: m.usedIds,
          isError: m.isError,
          images: asJson(s.images),
          evidence: asJson(s.evidence),
          attachments: asJson(m.attachments), // file metadata, plaintext (the files table and SQL joins use it)
          meta: asJson(s.meta),
          table: s.table == null ? Prisma.DbNull : asJson(s.table),
        };
      }),
    });
    return row;
  });
  const row = openRow(crypto, await withParent(saved));
  // Cross-chat recall: index the new messages shortly after the last save (debounced, in the background).
  scheduleIndex(id, uid ?? undefined);

  // Name it once, after the first complete exchange.
  const firstReply = messages.find((m) => m.role === "assistant" && !m.isError && m.content.trim());
  if (!row.title && firstUser && firstReply) {
    // Over the daily AI budget: name it from the first message instead of asking a model.
    const { title, source } = (await takeAi(userOf(req)))
      ? await generateTitle(firstUser, firstReply.content)
      : { title: fallbackTitle(firstUser), source: "fallback" as const };
    const named = await db().conversation.updateMany({ where: { id, title: null }, data: { title: crypto.seal(CONV, "title", title), titleSource: source } });
    if (named.count > 0) {
      const fresh = await db().conversation.findUnique({ where: { id }, include: WITH_PARENT });
      if (fresh) return void res.json(summary(openRow(crypto, fresh)));
    }
  }
  res.json(summary(row));
});

conversationsRouter.patch("/:id", async (req, res) => {
  db();
  const id = idParam(req.params.id);
  const { title, pinned, archived } = patchSchema.parse(req.body);
  const uid = userOf(req).id;
  const crypto = await userCrypto(uid);
  const row = await tx(async (c) => {
    const cur = await c.conversation.findFirst({ where: { id, userId: uid }, select: { pinnedAt: true, archivedAt: true } });
    if (!cur) throw new AppError(404, "not_found", "Conversation not found");
    const now = new Date();
    const data: Prisma.ConversationUpdateInput = {};
    if (title !== undefined) Object.assign(data, { title: crypto.seal(CONV, "title", title), titleSource: "user" });
    // Archiving unpins: an archived chat is out of the main list.
    if (archived === true) data.pinnedAt = null;
    else if (pinned !== undefined) data.pinnedAt = pinned ? (cur.pinnedAt ?? now) : null;
    if (archived !== undefined) data.archivedAt = archived ? (cur.archivedAt ?? now) : null;
    return c.conversation.update({ where: { id }, data, include: WITH_PARENT });
  });
  res.json(summary(openRow(crypto, row)));
});

conversationsRouter.delete("/:id", async (req, res) => {
  db();
  // Files attached in this chat go with it (storage objects and rows); see deleteConversations.
  await deleteConversations([idParam(req.params.id)], userOf(req).id);
  res.status(204).end();
});
