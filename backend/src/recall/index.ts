// Cross-chat recall index: keeps conversation_chunks (pgvector) in step with the
// saved conversations. Indexing is incremental (only new or changed chunks are
// embedded), debounced per chat, and never throws into a request. Deleting a
// chat or user removes its rows through ON DELETE CASCADE.
import { userCrypto } from "../crypto/userData.js";
import { MSG, openConversationText } from "../conversations/codec.js";
import { db, isDbUp, Prisma, tx } from "../db/prisma.js";
import { embedTexts } from "../embeddings/index.js";
import { log } from "../util/logger.js";
import { buildChunks, diffChunks } from "./chunks.js";
import { upsertSql } from "./sql.js";

const BACKFILL_BATCH = 300;
const BACKFILL_PAUSE_MS = 400;

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

  const crypto = await userCrypto(conv.userId);
  const text = openConversationText(crypto, conv);
  // Chunk hashes are keyed (blind index): a plain hash of a chunk would let anyone with DB access confirm guesses of its text.
  const wanted = buildChunks({
    title: text.title,
    summary: text.summary,
    preview: text.preview,
    messages: conv.messages.map((m) => ({ ...m, content: crypto.open(MSG, "content", m.content) })),
  }).map((ch) => ({ ...ch, hash: crypto.blindIndex("conversation_chunks", "content_hash", ch.hash) }));
  // Raw: reads the hash column of a table with a vector column.
  const rows = await db().$queryRaw<Array<{ ord: number; content_hash: string }>>`SELECT ord, content_hash FROM conversation_chunks WHERE conversation_id = ${id}::uuid`;
  const { remove, add } = diffChunks(new Map(rows.map((r) => [r.ord, r.content_hash])), wanted);

  // One request for all new chunks (embedTexts splits it by the provider's batch size, 64 by default).
  const vectors = add.length ? await embedTexts(add.map((c) => c.content), "document") : [];
  await tx(async (c) => {
    // The chat may have been deleted or switched off while embedding: write nothing then.
    const still = await c.conversation.findUnique({ where: { id }, select: { userId: true } });
    if (!still) return;
    if (remove.length) await c.$executeRaw`DELETE FROM conversation_chunks WHERE conversation_id = ${id}::uuid AND ord = ANY(${remove}::int[])`;
    for (let i = 0; i < add.length; i++) {
      await c.$executeRaw(upsertSql({ conversationId: id, uid: still.userId, ord: add[i].ord, kind: add[i].kind, content: crypto.seal("conversation_chunks", "content", add[i].content), hash: add[i].hash, vec: vectors[i] }));
    }
    await c.conversation.update({ where: { id }, data: { recallIndexedAt: new Date() } });
  });
  return add.length;
}

// ---- debounced scheduling ------------------------------------------------------------

/** A chat is indexed once it has been idle this long (each save restarts the wait). */
export const IDLE_MS = 3 * 60_000;
/** ...but never later than this after its first unindexed save, even while the user keeps chatting. */
export const MAX_WAIT_MS = 10 * 60_000;
/** ...or as soon as this many saves piled up (a long burst), after a short settle. */
export const MAX_SAVES = 8;
const SETTLE_MS = 5_000;
/** One user's chats are indexed at most this often (the embedding quota is shared by everyone). */
export const USER_GAP_MS = 60_000;

type Pending = { timer: NodeJS.Timeout; firstAt: number; saves: number; userId?: string };

/** Debounces and rate-limits indexing runs. Time and the run itself are injectable for tests. */
export class IndexScheduler {
  private pending = new Map<string, Pending>();
  private running = new Set<string>();
  private lastRun = new Map<string, number>();
  constructor(
    private run: (id: string) => Promise<unknown>,
    private o: { idleMs?: number; maxWaitMs?: number; maxSaves?: number; settleMs?: number; userGapMs?: number } = {},
  ) {}

  /** Notes a save of chat [id]: it is indexed after the idle wait, the max wait or a burst of saves, whichever comes first. */
  schedule(id: string, userId?: string): void {
    const prev = this.pending.get(id);
    if (prev) clearTimeout(prev.timer);
    const now = Date.now();
    const firstAt = prev?.firstAt ?? now;
    const saves = (prev?.saves ?? 0) + 1;
    const untilMax = Math.max(0, firstAt + (this.o.maxWaitMs ?? MAX_WAIT_MS) - now);
    const burst = saves >= (this.o.maxSaves ?? MAX_SAVES);
    const delay = Math.min(burst ? (this.o.settleMs ?? SETTLE_MS) : (this.o.idleMs ?? IDLE_MS), untilMax);
    this.arm(id, { firstAt, saves, userId: userId ?? prev?.userId }, delay);
  }

  private arm(id: string, st: Omit<Pending, "timer">, delay: number): void {
    const timer = setTimeout(() => this.fire(id), delay);
    timer.unref();
    this.pending.set(id, { ...st, timer });
  }

  private fire(id: string): void {
    const st = this.pending.get(id);
    if (!st) return;
    // Busy with this chat, or its user indexed a chat a moment ago: try again shortly.
    const gapLeft = st.userId ? (this.lastRun.get(st.userId) ?? -Infinity) + (this.o.userGapMs ?? USER_GAP_MS) - Date.now() : 0;
    if (this.running.has(id) || gapLeft > 0) return this.arm(id, st, Math.max(gapLeft, this.o.settleMs ?? SETTLE_MS));
    this.pending.delete(id);
    this.running.add(id);
    if (st.userId) this.lastRun.set(st.userId, Date.now());
    this.run(id)
      .catch((e) => log.warn("chat recall indexing failed", { message: String((e as Error).message ?? e).slice(0, 140) }))
      .finally(() => this.running.delete(id));
  }

  cancel(id: string): void {
    const st = this.pending.get(id);
    if (st) clearTimeout(st.timer);
    this.pending.delete(id);
  }

  get size(): number {
    return this.pending.size;
  }
}

const scheduler = new IndexScheduler((id) => indexConversation(id));

/** Indexes [id] once the chat has gone quiet (see [IndexScheduler]). Fire and forget. */
export function scheduleIndex(id: string, userId?: string): void {
  scheduler.schedule(id, userId);
}

/** Cancels a pending index run (the chat was deleted). */
export function cancelIndex(id: string): void {
  scheduler.cancel(id);
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
