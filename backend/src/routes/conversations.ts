import { Router } from "express";
import { z } from "zod";
import { getPool, query, withTx } from "../db/pool.js";
import { AppError } from "../util/errors.js";
import { generateTitle } from "../conversations/title.js";
import { mergeBriefing, type MergeChat } from "../conversations/merge.js";
import { deleteFile, getFileRow } from "../files/store.js";

export const conversationsRouter = Router();

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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
  .refine((t) => JSON.stringify(t).length <= 40_000, "table transcript too large");

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

type Row = {
  id: string;
  title: string | null;
  title_source: string | null;
  message_count: number;
  preview: string | null;
  pinned_at: Date | null;
  archived_at: Date | null;
  origin: "fork" | "merge" | null;
  forked_from: string | null;
  fork_point: number | null;
  merged_from: string[] | null;
  parent_title?: string | null;
  created_at: Date;
  updated_at: Date;
};

// Row columns plus the fork parent's title, for SELECT and RETURNING lists.
const COLS = "*, (SELECT p.title FROM conversations p WHERE p.id = conversations.forked_from) AS parent_title";

const summary = (r: Row) => ({
  id: r.id,
  title: r.title,
  titleSource: r.title_source,
  messageCount: r.message_count,
  preview: r.preview,
  pinned: r.pinned_at != null,
  archived: r.archived_at != null,
  origin: r.origin ?? null,
  forkedFrom: r.forked_from ?? null,
  forkPoint: r.fork_point ?? null,
  parent: r.forked_from ? { id: r.forked_from, title: r.parent_title ?? null } : null,
  mergedFrom: r.merged_from ?? [],
  createdAt: r.created_at.toISOString(),
  updatedAt: r.updated_at.toISOString(),
});

// GET /conversations?q=&limit=&before=<ISO updatedAt>&archived=1
// Pinned chats come first; archived ones are listed only with archived=1.
conversationsRouter.get("/", async (req, res) => {
  getPool();
  const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 100);
  const q = typeof req.query.q === "string" ? req.query.q.trim().slice(0, 100) : "";
  const archived = req.query.archived === "1" || req.query.archived === "true";
  const before = typeof req.query.before === "string" && !Number.isNaN(Date.parse(req.query.before)) ? req.query.before : null;
  const { rows } = await query<Row>(
    `SELECT ${COLS} FROM conversations
     WHERE ($1 = '' OR title ILIKE '%' || $1 || '%' OR EXISTS (
         SELECT 1 FROM conversation_messages m
         WHERE m.conversation_id = conversations.id AND m.content ILIKE '%' || $1 || '%'))
       AND ($2::timestamptz IS NULL OR updated_at < $2::timestamptz)
       AND ((archived_at IS NOT NULL) = $4)
     ORDER BY pinned_at IS NOT NULL DESC, pinned_at DESC NULLS LAST, updated_at DESC LIMIT $3`,
    [q, before, limit, archived],
  );
  res.json({ conversations: rows.map(summary) });
});

/** A conversation with its messages, as GET /:id returns it; null when it does not exist. */
async function loadConversation(id: string) {
  const { rows } = await query<Row>(`SELECT ${COLS} FROM conversations WHERE id = $1`, [id]);
  if (!rows[0]) return null;
  const messages = await query(
    `SELECT role, content, model, citations, used_ids, is_error, images, evidence, attachments, meta, "table" FROM conversation_messages
     WHERE conversation_id = $1 ORDER BY position`,
    [id],
  );
  return {
    ...summary(rows[0]),
    messages: messages.rows.map((m) => ({
      role: m.role,
      content: m.content,
      model: m.model,
      citations: m.citations,
      usedIds: m.used_ids,
      isError: m.is_error,
      images: m.images,
      evidence: m.evidence,
      attachments: m.attachments ?? [],
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
  getPool();
  const { ids } = mergeSchema.parse(req.body);
  const [a, b] = ids.map(idParam);
  if (a === b) throw new AppError(400, "same_conversation", "Pick two different chats to merge");
  const chats: MergeChat[] = [];
  for (const id of [a, b]) {
    const conv = await loadConversation(id);
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
  const newId = await withTx(async (c) => {
    const { rows } = await c.query<{ id: string }>(
      `INSERT INTO conversations (id, title, title_source, message_count, preview, origin, merged_from)
       VALUES (gen_random_uuid(), $1, 'derived', 1, $2, 'merge', $3::uuid[]) RETURNING id`,
      [title, preview, [a, b]],
    );
    await c.query(
      `INSERT INTO conversation_messages (conversation_id, position, role, content, meta) VALUES ($1, 0, 'context', $2, $3::jsonb)`,
      [rows[0].id, briefing.text, JSON.stringify(meta)],
    );
    return rows[0].id;
  });
  res.status(201).json(await loadConversation(newId));
});

// POST /conversations/:id/fork {at}: a copy of the first `at` saved messages.
conversationsRouter.post("/:id/fork", async (req, res) => {
  getPool();
  const id = idParam(req.params.id);
  const { at } = forkSchema.parse(req.body);
  const newId = await withTx(async (c) => {
    const { rows } = await c.query<Row>("SELECT * FROM conversations WHERE id = $1 FOR UPDATE", [id]);
    const parent = rows[0];
    if (!parent) throw new AppError(404, "not_found", "Conversation not found");
    const count = Number((await c.query("SELECT count(*)::int AS n FROM conversation_messages WHERE conversation_id = $1", [id])).rows[0].n);
    if (at > count) throw new AppError(400, "bad_request", `at must be between 1 and ${count}`);
    const base = (parent.title || parent.preview || "Untitled chat").replace(/ · fork$/, "");
    const created = await c.query<{ id: string }>(
      `INSERT INTO conversations (id, title, title_source, message_count, preview, origin, forked_from, fork_point)
       VALUES (gen_random_uuid(), $1, 'derived', $2, $3, 'fork', $4, $2) RETURNING id`,
      [`${base.slice(0, 120 - FORK_SUFFIX.length)}${FORK_SUFFIX}`, at, parent.preview, id],
    );
    // Every message column is copied, so columns added later come along too.
    const { rows: colRows } = await c.query<{ column_name: string }>(
      `SELECT column_name FROM information_schema.columns
        WHERE table_schema = current_schema() AND table_name = 'conversation_messages' AND column_name <> 'conversation_id'`,
    );
    const cols = colRows.map((r) => `"${r.column_name}"`).join(", ");
    await c.query(
      `INSERT INTO conversation_messages (conversation_id, ${cols})
       SELECT $2, ${cols} FROM conversation_messages WHERE conversation_id = $1 AND position < $3`,
      [id, created.rows[0].id, at],
    );
    return created.rows[0].id;
  });
  res.status(201).json(await loadConversation(newId));
});

conversationsRouter.get("/:id", async (req, res) => {
  getPool();
  const conv = await loadConversation(idParam(req.params.id));
  if (!conv) throw new AppError(404, "not_found", "Conversation not found");
  res.json(conv);
});

// Full replace of the conversation; the app is the source of truth.
conversationsRouter.put("/:id", async (req, res) => {
  getPool();
  const id = idParam(req.params.id);
  const { messages } = putSchema.parse(req.body);
  const firstUser = messages.find((m) => m.role === "user")?.content ?? "";
  const preview = firstUser.replace(/\s+/g, " ").trim().slice(0, 140);

  const row = await withTx(async (c) => {
    const saved = await c.query<Row>(
      `INSERT INTO conversations (id, message_count, preview) VALUES ($1, $2, NULLIF($3, ''))
       ON CONFLICT (id) DO UPDATE SET message_count = EXCLUDED.message_count,
         preview = COALESCE(EXCLUDED.preview, conversations.preview), updated_at = now()
       RETURNING ${COLS}`,
      [id, messages.length, preview],
    );
    await c.query("DELETE FROM conversation_messages WHERE conversation_id = $1", [id]);
    await c.query(
      `INSERT INTO conversation_messages (conversation_id, position, role, content, model, citations, used_ids, is_error, images, evidence, attachments, meta, "table")
       SELECT $1, t.position, t.role, t.content, t.model, t.citations, t.used_ids, t.is_error, t.images, t.evidence, t.attachments, COALESCE(t.meta, '{}'), t."table"
       FROM jsonb_to_recordset($2::jsonb)
         AS t(position int, role text, content text, model text, citations jsonb, used_ids text[], is_error boolean, images jsonb, evidence jsonb, attachments jsonb, meta jsonb, "table" jsonb)`,
      [
        id,
        JSON.stringify(
          messages.map((m, position) => ({
            position,
            role: m.role,
            content: m.content,
            model: m.model ?? null,
            citations: m.citations,
            used_ids: m.usedIds,
            is_error: m.isError,
            images: m.images,
            evidence: m.evidence,
            attachments: m.attachments,
            meta: m.meta,
            table: m.table ?? null,
          })),
        ),
      ],
    );
    return saved.rows[0];
  });

  // Name it once, after the first complete exchange.
  const firstReply = messages.find((m) => m.role === "assistant" && !m.isError && m.content.trim());
  if (!row.title && firstUser && firstReply) {
    const { title, source } = await generateTitle(firstUser, firstReply.content);
    const named = await query<Row>(
      `UPDATE conversations SET title = $2, title_source = $3 WHERE id = $1 AND title IS NULL RETURNING ${COLS}`,
      [id, title, source],
    );
    if (named.rows[0]) return void res.json(summary(named.rows[0]));
  }
  res.json(summary(row));
});

conversationsRouter.patch("/:id", async (req, res) => {
  getPool();
  const id = idParam(req.params.id);
  const { title, pinned, archived } = patchSchema.parse(req.body);
  // Archiving unpins: an archived chat is out of the main list.
  const unpin = archived === true;
  const { rows } = await query<Row>(
    `UPDATE conversations SET
       title = COALESCE($2, title),
       title_source = CASE WHEN $2::text IS NULL THEN title_source ELSE 'user' END,
       pinned_at = CASE WHEN $5::boolean THEN NULL WHEN $3::boolean IS NULL THEN pinned_at WHEN $3 THEN COALESCE(pinned_at, now()) ELSE NULL END,
       archived_at = CASE WHEN $4::boolean IS NULL THEN archived_at WHEN $4 THEN COALESCE(archived_at, now()) ELSE NULL END
     WHERE id = $1 RETURNING ${COLS}`,
    [id, title ?? null, pinned ?? null, archived ?? null, unpin],
  );
  if (!rows[0]) throw new AppError(404, "not_found", "Conversation not found");
  res.json(summary(rows[0]));
});

conversationsRouter.delete("/:id", async (req, res) => {
  getPool();
  const id = idParam(req.params.id);
  // Files attached in this chat go with it (storage objects and rows).
  const { rows: attached } = await query<{ id: string }>(
    `SELECT DISTINCT (a->>'id') AS id
       FROM conversation_messages m, jsonb_array_elements(m.attachments) a
      WHERE m.conversation_id = $1 AND a ? 'id'
     UNION
     SELECT id::text FROM files WHERE conversation_id = $1`,
    [id],
  );
  await query("DELETE FROM conversations WHERE id = $1", [id]);
  for (const { id: fileId } of attached) {
    // Forks share attachments by reference: a file another chat still uses stays, owned by that chat.
    const { rows: users } = await query<{ conversation_id: string }>(
      `SELECT conversation_id FROM conversation_messages
        WHERE attachments @> jsonb_build_array(jsonb_build_object('id', $1::text)) LIMIT 1`,
      [fileId],
    );
    if (users[0]) {
      await query("UPDATE files SET conversation_id = $2 WHERE id::text = $1 AND conversation_id = $3", [fileId, users[0].conversation_id, id]);
      continue;
    }
    const row = await getFileRow(fileId).catch(() => null);
    if (row) await deleteFile(row).catch(() => undefined);
  }
  res.status(204).end();
});
