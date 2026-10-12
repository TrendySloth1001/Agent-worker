// Cross-chat recall index: keeps conversation_chunks (pgvector) in step with the
// saved conversations. Indexing is incremental (only new or changed chunks are
// embedded), debounced per chat, and never throws into a request. Deleting a
// chat or user removes its rows through ON DELETE CASCADE.
import { db, isDbUp, Prisma, tx } from "../db/prisma.js";
import { embedTexts } from "../embeddings/index.js";
import { log } from "../util/logger.js";
import { buildChunks, diffChunks } from "./chunks.js";
import { upsertSql } from "./sql.js";

/** Wait this long after the last save of a chat before indexing it. */
export const DEBOUNCE_MS = 20_000;
const BACKFILL_BATCH = 300;
const BACKFILL_PAUSE_MS = 400;
const EMBED_BATCH = 16;

/** Cross-chat recall switch of a user (default on; the dev bypass user without an id counts as on). */
export async function chatRecallEnabled(userId: string | null): Promise<boolean> {
  if (!userId) return true;
  const u = await db().user.findUnique({ where: { id: userId }, select: { chatRecallEnabled: true } });
  return u?.chatRecallEnabled ?? false;
}

/** Switches cross-chat recall for a user: off drops their index, on rebuilds it in the background. */
export async function setChatRecallEnabled(userId: string, enabled: boolean): Promise<void> {
  const prev = await chatRecallEnabled(userId);
  await db().user.update({ where: { id: userId }, data: { chatRecallEnabled: enabled } });
  if (!enabled) {
    await dropUserIndex(userId);
  } else if (!prev) void backfillRecall(userId);
}

/** Brings the index of one chat up to date. Returns the number of chunks embedded, or null when skipped. */
export async function indexConversation(id: string): Promise<number | null> {
  if (!isDbUp()) return null;
  const conv = await db().conversation.findUnique({
    where: { id },
    select: { id: true, userId: true, title: true, summary: true, preview: true, updatedAt: true, messages: { orderBy: { position: "asc" }, select: { role: true, content: true, isError: true } } },
  });
  if (!conv) return null;
  if (!(await chatRecallEnabled(conv.userId))) return null;

  const wanted = buildChunks({ title: conv.title, summary: conv.summary, preview: conv.preview, messages: conv.messages });
  // Raw: reads the hash column of a table with a vector column.
  const rows = await db().$queryRaw<Array<{ ord: number; content_hash: string }>>`SELECT ord, content_hash FROM conversation_chunks WHERE conversation_id = ${id}::uuid`;
  const { remove, add } = diffChunks(new Map(rows.map((r) => [r.ord, r.content_hash])), wanted);

  const vectors: number[][] = [];
  for (let i = 0; i < add.length; i += EMBED_BATCH) {
    vectors.push(...(await embedTexts(add.slice(i, i + EMBED_BATCH).map((c) => c.content), "document")));
  }
  await tx(async (c) => {
    // The chat may have been deleted or switched off while embedding: write nothing then.
    const still = await c.conversation.findUnique({ where: { id }, select: { userId: true } });
    if (!still) return;
    if (remove.length) await c.$executeRaw`DELETE FROM conversation_chunks WHERE conversation_id = ${id}::uuid AND ord = ANY(${remove}::int[])`;
    for (let i = 0; i < add.length; i++) {
      await c.$executeRaw(upsertSql({ conversationId: id, uid: still.userId, ord: add[i].ord, kind: add[i].kind, content: add[i].content, hash: add[i].hash, vec: vectors[i] }));
    }
    await c.conversation.update({ where: { id }, data: { recallIndexedAt: new Date() } });
  });
  return add.length;
}

// ---- debounced scheduling ------------------------------------------------------------

const timers = new Map<string, NodeJS.Timeout>();
const running = new Set<string>();

/** Indexes [id] shortly after the last save (each save restarts the timer). Fire and forget. */
export function scheduleIndex(id: string, delayMs = DEBOUNCE_MS): void {
  const prev = timers.get(id);
  if (prev) clearTimeout(prev);
  const t = setTimeout(() => {
    timers.delete(id);
    if (running.has(id)) return scheduleIndex(id, delayMs);
    running.add(id);
    indexConversation(id)
      .catch((e) => log.warn("chat recall indexing failed", { message: String((e as Error).message ?? e).slice(0, 140) }))
      .finally(() => running.delete(id));
  }, delayMs);
  t.unref();
  timers.set(id, t);
}

/** Cancels a pending index run (the chat was deleted). */
export function cancelIndex(id: string): void {
  const t = timers.get(id);
  if (t) clearTimeout(t);
  timers.delete(id);
}

// ---- backfill ---------------------------------------------------------------------------

let backfilling = false;

/**
 * Indexes chats that have no (or an outdated) index, newest first, for users
 * with recall on. Slow on purpose (embedding quota); safe to call repeatedly.
 * [userId] limits it to one user (when they switch recall back on).
 */
export async function backfillRecall(userId?: string): Promise<number> {
  if (backfilling || !isDbUp()) return 0;
  backfilling = true;
  let done = 0;
  try {
    // Raw: compares two columns of the same row, which Prisma filters cannot express.
    const ids = await db().$queryRaw<Array<{ id: string }>>`
      SELECT c.id::text AS id FROM conversations c
      LEFT JOIN users u ON u.id = c.user_id
      WHERE c.message_count > 0
        AND (c.recall_indexed_at IS NULL OR c.recall_indexed_at < c.updated_at)
        AND (c.user_id IS NULL OR u.chat_recall_enabled)
        ${userId ? Prisma.sql`AND c.user_id = ${userId}::uuid` : Prisma.empty}
      ORDER BY c.updated_at DESC LIMIT ${BACKFILL_BATCH}`;
    let failures = 0;
    for (const { id } of ids) {
      try {
        await indexConversation(id);
        done++;
        failures = 0;
      } catch (e) {
        log.warn("chat recall backfill failed", { message: String((e as Error).message ?? e).slice(0, 140) });
        if (++failures >= 2) break; // embeddings are down: try again on the next start
      }
      await new Promise((r) => setTimeout(r, BACKFILL_PAUSE_MS));
    }
    if (done) log.info("chat recall backfill", { indexed: done });
  } catch (e) {
    log.warn("chat recall backfill error", { message: String((e as Error).message ?? e).slice(0, 140) });
  } finally {
    backfilling = false;
  }
  return done;
}

/** Removes a user's whole index (recall switched off). */
export async function dropUserIndex(userId: string): Promise<void> {
  await db().conversationChunk.deleteMany({ where: { userId } });
  await db().conversation.updateMany({ where: { userId }, data: { recallIndexedAt: null } });
}

/** After an embedding-model switch the old vectors are meaningless: drop them, the backfill rebuilds. */
export async function dropAllIndexes(): Promise<void> {
  await db().conversationChunk.deleteMany({});
  await db().conversation.updateMany({ data: { recallIndexedAt: null } });
}
