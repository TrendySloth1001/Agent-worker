import { randomUUID } from "node:crypto";
import { Router } from "express";
import { z } from "zod";
import { db, Prisma, tx } from "../db/prisma.js";
import type { Conversation } from "../generated/prisma/client.js";
import { AppError } from "../util/errors.js";
import { generateTitle } from "../conversations/title.js";
import { mergeBriefing, type MergeChat } from "../conversations/merge.js";
import { deleteFile, getFileRow } from "../files/store.js";
import { userOf } from "../auth/context.js";

export const conversationsRouter = Router();

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// `files.id::text` is lowercase, so only lowercase ids ever matched a row.
const FILE_ID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const citationSchema = z
  .object({
    id: z.string(),
    kind: z.enum(["kb", "web", "file"]),
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
  attachments: z.array(attachmentSchema).max(6).default([]),
  isError: z.boolean().default(false),
  table: tableSchema.nullish(),
});

const putSchema = z.object({ messages: z.array(messageSchema).min(1).max(2000) });
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
  const rows = await db().conversation.findMany({
    where: {
      userId: uid,
      archivedAt: archived ? { not: null } : null,
      ...(before ? { updatedAt: { lt: before } } : {}),
      ...(q
        ? {
            OR: [
              { title: { contains: q, mode: "insensitive" } },
              { messages: { some: { content: { contains: q, mode: "insensitive" } } } },
            ],
          }
        : {}),
    },
    // Pinned first (most recently pinned on top), then by activity.
    orderBy: [{ pinnedAt: { sort: "desc", nulls: "last" } }, { updatedAt: "desc" }],
    take: limit,
    include: WITH_PARENT,
  });
  res.json({ conversations: rows.map(summary) });
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
  return {
    ...summary(row),
    messages: row.messages.map((m) => ({
      role: m.role,
      content: m.content,
      model: m.model,
      citations: m.citations,
      usedIds: m.usedIds,
      isError: m.isError,
      images: m.images,
      evidence: m.evidence,
      // Stored as the app sent it (validated attachment objects).
      attachments: (m.attachments ?? []) as Array<Record<string, unknown>>,
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
  const created = await db().conversation.create({
    data: {
      id: randomUUID(),
      title,
      titleSource: "derived",
      messageCount: 1,
      preview,
      origin: "merge",
      mergedFrom: [a, b],
      userId: uid,
      messages: { create: { position: 0, role: "context", content: briefing.text, meta: asJson(meta) } },
    },
    select: { id: true },
  });
  res.status(201).json(await loadConversation(created.id, uid));
});

// POST /conversations/:id/fork {at}: a copy of the first `at` saved messages.
conversationsRouter.post("/:id/fork", async (req, res) => {
  db();
  const id = idParam(req.params.id);
  const { at } = forkSchema.parse(req.body);
  const uid = userOf(req).id;
  const newId = await tx(async (c) => {
    // Raw: Prisma has no SELECT ... FOR UPDATE; the lock keeps the parent stable while copying.
    await c.$queryRaw`SELECT 1 FROM conversations WHERE id = ${id}::uuid AND user_id IS NOT DISTINCT FROM ${uid}::uuid FOR UPDATE`;
    const parent = await c.conversation.findFirst({ where: { id, userId: uid }, select: { title: true, preview: true } });
    if (!parent) throw new AppError(404, "not_found", "Conversation not found");
    const count = await c.conversationMessage.count({ where: { conversationId: id } });
    if (at > count) throw new AppError(400, "bad_request", `at must be between 1 and ${count}`);
    const base = (parent.title || parent.preview || "Untitled chat").replace(/ · fork$/, "");
    const created = await c.conversation.create({
      data: {
        id: randomUUID(),
        title: `${base.slice(0, 120 - FORK_SUFFIX.length)}${FORK_SUFFIX}`,
        titleSource: "derived",
        messageCount: at,
        preview: parent.preview,
        origin: "fork",
        forkedFrom: id,
        forkPoint: at,
        userId: uid,
      },
      select: { id: true },
    });
    // Every message field is copied, so fields added to the model later come along too.
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
  const { messages } = putSchema.parse(req.body);
  const uid = userOf(req).id;
  const firstUser = messages.find((m) => m.role === "user")?.content ?? "";
  const preview = firstUser.replace(/\s+/g, " ").trim().slice(0, 140);

  const saved = await tx(async (c) => {
    // Another user's id: nothing is written (and it reads as not found).
    const owner = await c.conversation.findUnique({ where: { id }, select: { userId: true } });
    if (owner && owner.userId !== uid) throw new AppError(404, "not_found", "Conversation not found");
    // A plain upsert by primary key runs as INSERT ... ON CONFLICT, so concurrent first saves do not collide.
    const row = await c.conversation.upsert({
      where: { id },
      create: { id, messageCount: messages.length, preview: preview || null, userId: uid },
      update: { messageCount: messages.length, ...(preview ? { preview } : {}), updatedAt: new Date() },
    });
    if (row.userId !== uid) throw new AppError(404, "not_found", "Conversation not found");
    await c.conversationMessage.deleteMany({ where: { conversationId: id } });
    await c.conversationMessage.createMany({
      data: messages.map((m, position) => ({
        conversationId: id,
        position,
        role: m.role,
        content: m.content,
        model: m.model ?? null,
        citations: asJson(m.citations),
        usedIds: m.usedIds,
        isError: m.isError,
        images: asJson(m.images),
        evidence: asJson(m.evidence),
        attachments: asJson(m.attachments),
        meta: asJson(m.meta ?? {}),
        table: m.table == null ? Prisma.DbNull : asJson(m.table),
      })),
    });
    return row;
  });
  const row = await withParent(saved);

  // Name it once, after the first complete exchange.
  const firstReply = messages.find((m) => m.role === "assistant" && !m.isError && m.content.trim());
  if (!row.title && firstUser && firstReply) {
    const { title, source } = await generateTitle(firstUser, firstReply.content);
    const named = await db().conversation.updateMany({ where: { id, title: null }, data: { title, titleSource: source } });
    if (named.count > 0) {
      const fresh = await db().conversation.findUnique({ where: { id }, include: WITH_PARENT });
      if (fresh) return void res.json(summary(fresh));
    }
  }
  res.json(summary(row));
});

conversationsRouter.patch("/:id", async (req, res) => {
  db();
  const id = idParam(req.params.id);
  const { title, pinned, archived } = patchSchema.parse(req.body);
  const uid = userOf(req).id;
  const row = await tx(async (c) => {
    const cur = await c.conversation.findFirst({ where: { id, userId: uid }, select: { pinnedAt: true, archivedAt: true } });
    if (!cur) throw new AppError(404, "not_found", "Conversation not found");
    const now = new Date();
    const data: Prisma.ConversationUpdateInput = {};
    if (title !== undefined) Object.assign(data, { title, titleSource: "user" });
    // Archiving unpins: an archived chat is out of the main list.
    if (archived === true) data.pinnedAt = null;
    else if (pinned !== undefined) data.pinnedAt = pinned ? (cur.pinnedAt ?? now) : null;
    if (archived !== undefined) data.archivedAt = archived ? (cur.archivedAt ?? now) : null;
    return c.conversation.update({ where: { id }, data, include: WITH_PARENT });
  });
  res.json(summary(row));
});

conversationsRouter.delete("/:id", async (req, res) => {
  db();
  const id = idParam(req.params.id);
  const uid = userOf(req).id;
  const own = await db().conversation.findFirst({ where: { id, userId: uid }, select: { id: true } });
  if (!own) return void res.status(204).end();
  // Files attached in this chat go with it (storage objects and rows).
  const [msgs, files] = await Promise.all([
    db().conversationMessage.findMany({ where: { conversationId: id }, select: { attachments: true } }),
    db().storedFile.findMany({ where: { conversationId: id }, select: { id: true } }),
  ]);
  const attached = new Set<string>();
  for (const m of msgs) {
    if (!Array.isArray(m.attachments)) continue;
    for (const a of m.attachments) {
      // Same as `a ? 'id'` / `a->>'id'`: any attachment object with an id (as text).
      if (a && typeof a === "object" && !Array.isArray(a) && "id" in a && a.id != null) {
        attached.add(typeof a.id === "string" ? a.id : JSON.stringify(a.id));
      }
    }
  }
  for (const f of files) attached.add(f.id);
  await db().conversation.deleteMany({ where: { id } });
  for (const fileId of attached) {
    // Forks share attachments by reference: a file another chat still uses stays, owned by that chat.
    // Raw: jsonb containment (`@>`) over the attachments array has no Prisma filter.
    const users = await db().$queryRaw<Array<{ conversation_id: string }>>`
      SELECT m.conversation_id FROM conversation_messages m JOIN conversations c ON c.id = m.conversation_id
       WHERE m.attachments @> jsonb_build_array(jsonb_build_object('id', ${fileId}::text)) AND c.user_id IS NOT DISTINCT FROM ${uid}::uuid LIMIT 1`;
    if (users[0]) {
      // File ids are uuids; anything else in the JSON cannot match a files row.
      if (FILE_ID_RE.test(fileId)) {
        await db().storedFile.updateMany({ where: { id: fileId, conversationId: id, userId: uid }, data: { conversationId: users[0].conversation_id } });
      }
      continue;
    }
    const row = await getFileRow(fileId).catch(() => null);
    if (row) await deleteFile(row).catch(() => undefined);
  }
  res.status(204).end();
});
