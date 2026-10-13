// Memory persistence. Every function takes the user id and filters by it, so one
// user can never read or change another's memories. Embeddings are raw SQL
// (pgvector); everything else goes through Prisma.
import { db, Prisma } from "../db/prisma.js";
import { toVector } from "../db/vector.js";
import { embedTexts } from "../embeddings/index.js";
import { log } from "../util/logger.js";
import { userCrypto, type UserCrypto } from "../crypto/userData.js";
import { slotOf } from "./slots.js";
import { isUuid } from "../docs/store.js";
import type { ExistingMemory, Kind } from "./logic.js";

export type MemoryRow = {
  id: string;
  text: string;
  kind: Kind;
  pinned: boolean;
  slot: string | null;
  sourceConversationId: string | null;
  createdAt: Date;
  updatedAt: Date;
  lastUsedAt: Date | null;
};

const SELECT = { id: true, text: true, kind: true, pinned: true, slot: true, slotEnc: true, sourceConversationId: true, createdAt: true, updatedAt: true, lastUsedAt: true } as const;

// ---- encryption at rest -----------------------------------------------------------
// `text` is sealed. `slot` holds a keyed blind index (`h1:...`) so "one memory per slot" and slot lookups keep
// working in SQL; the real slot name is sealed in `slot_enc`. Legacy rows (plaintext text/slot) read as before.
const T = "memories";
type Stored = { text: string; slot: string | null; slotEnc?: string | null };

function openMem<R extends Stored>(c: UserCrypto, r: R): Omit<R, "slotEnc"> & { text: string; slot: string | null } {
  const { slotEnc, ...rest } = r;
  const text = c.open(T, "text", r.text);
  // Hashed slot without its sealed name (should not happen): infer it from the text, like an unslotted memory.
  const slot = slotEnc ? c.open(T, "slot_enc", slotEnc) : r.slot?.startsWith("h1:") ? slotOf(text) : r.slot;
  return { ...rest, text, slot };
}
const sealSlot = (c: UserCrypto, slot: string | null | undefined) => (slot ? { slot: c.blindIndex(T, "slot", slot), slotEnc: c.seal(T, "slot_enc", slot) } : { slot: null, slotEnc: null });
const asRow = (r: { kind: string } & Omit<MemoryRow, "kind">): MemoryRow => ({ ...r, kind: r.kind as Kind });

export const publicMemory = (m: MemoryRow) => ({
  id: m.id,
  text: m.text,
  kind: m.kind,
  pinned: m.pinned,
  slot: m.slot,
  conversationId: m.sourceConversationId,
  createdAt: m.createdAt.toISOString(),
  updatedAt: m.updatedAt.toISOString(),
  lastUsedAt: m.lastUsedAt?.toISOString() ?? null,
});

// ---- settings ---------------------------------------------------------------------

export async function memoryEnabled(userId: string | null): Promise<boolean> {
  if (!userId) return false;
  const u = await db().user.findUnique({ where: { id: userId }, select: { memoryEnabled: true } });
  return u?.memoryEnabled ?? false;
}

export async function setMemoryEnabled(userId: string, enabled: boolean): Promise<void> {
  await db().user.update({ where: { id: userId }, data: { memoryEnabled: enabled } });
}

// ---- embeddings -------------------------------------------------------------------

/** Embeds memory texts; null per text when the embedding service is down (the memory is still saved). */
export async function embedMemory(text: string): Promise<number[] | null> {
  try {
    return (await embedTexts([text], "document"))[0];
  } catch (e) {
    log.warn("memory embedding failed", { error: (e as Error).message?.slice(0, 120) });
    return null;
  }
}

async function setEmbedding(id: string, vec: number[] | null): Promise<void> {
  await db().$executeRaw`UPDATE memories SET embedding = ${vec ? toVector(vec) : null}::vector WHERE id = ${id}::uuid`;
}

// ---- CRUD -------------------------------------------------------------------------

export async function listMemories(userId: string, opts: { q?: string; limit?: number; offset?: number } = {}): Promise<{ items: MemoryRow[]; total: number }> {
  const q = opts.q?.trim();
  const c = await userCrypto(userId);
  const limit = Math.min(opts.limit ?? 200, 500);
  const offset = opts.offset ?? 0;
  const where: Prisma.MemoryWhereInput = { userId };
  const order = [{ pinned: "desc" as const }, { updatedAt: "desc" as const }];
  if (!q) {
    const [rows, total] = await Promise.all([db().memory.findMany({ where, select: SELECT, orderBy: order, take: limit, skip: offset }), db().memory.count({ where })]);
    return { items: rows.map((r) => asRow(openMem(c, r))), total };
  }
  // Text is encrypted: filter the user's memories (a few hundred at most) after decrypting.
  const needle = q.toLowerCase();
  const all = (await db().memory.findMany({ where, select: SELECT, orderBy: order, take: MEMORY_SCAN_MAX })).map((r) => asRow(openMem(c, r)));
  const hits = all.filter((m) => m.text.toLowerCase().includes(needle));
  return { items: hits.slice(offset, offset + limit), total: hits.length };
}

export async function countMemories(userId: string): Promise<number> {
  return db().memory.count({ where: { userId } });
}

/** Most memories one filtered listing decrypts (the cap on how many a user can keep is far lower). */
const MEMORY_SCAN_MAX = 2000;

/** Unique violation on memories_user_slot (another write took the slot first). */
const isSlotConflict = (e: unknown) => e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002";

export async function createMemory(userId: string, input: { text: string; kind: Kind; pinned?: boolean; slot?: string | null; conversationId?: string | null; vec?: number[] | null }): Promise<MemoryRow> {
  const c = await userCrypto(userId);
  const data = {
    userId,
    text: c.seal(T, "text", input.text),
    kind: input.kind,
    pinned: input.pinned ?? false,
    ...sealSlot(c, input.slot),
    sourceConversationId: input.conversationId && isUuid(input.conversationId) ? input.conversationId : null,
  };
  const row = await db()
    .memory.create({ data, select: SELECT })
    .catch((e) => {
      if (!data.slot || !isSlotConflict(e)) throw e;
      return db().memory.create({ data: { ...data, slot: null, slotEnc: null }, select: SELECT });
    });
  const vec = input.vec === undefined ? await embedMemory(input.text) : input.vec;
  if (vec) await setEmbedding(row.id, vec);
  return asRow(openMem(c, row));
}

export async function updateMemory(userId: string, id: string, patch: { text?: string; kind?: Kind; pinned?: boolean; slot?: string | null }, vec?: number[] | null): Promise<MemoryRow | null> {
  if (!isUuid(id)) return null;
  const c = await userCrypto(userId);
  const { slot, text, ...others } = patch;
  const data = { ...others, ...(text !== undefined ? { text: c.seal(T, "text", text) } : {}), ...(slot !== undefined ? sealSlot(c, slot) : {}) };
  const res = await db()
    .memory.updateMany({ where: { id, userId }, data })
    .catch((e) => {
      if (!slot || !isSlotConflict(e)) throw e;
      const { slot: _slot, slotEnc: _slotEnc, ...rest } = data as typeof data & { slot?: unknown; slotEnc?: unknown };
      return db().memory.updateMany({ where: { id, userId }, data: rest });
    });
  if (res.count === 0) return null;
  if (patch.text !== undefined) {
    const v = vec === undefined ? await embedMemory(patch.text) : vec;
    await setEmbedding(id, v);
  }
  const row = await db().memory.findFirst({ where: { id, userId }, select: SELECT });
  return row ? asRow(openMem(c, row)) : null;
}

export async function deleteMemory(userId: string, id: string): Promise<boolean> {
  if (!isUuid(id)) return false;
  return (await db().memory.deleteMany({ where: { id, userId } })).count > 0;
}

export async function deleteAllMemories(userId: string): Promise<number> {
  return (await db().memory.deleteMany({ where: { userId } })).count;
}

/** "Forget everything about me" from chat: pinned memories stay (only the Memory screen clears those). */
export async function deleteUnpinnedMemories(userId: string): Promise<string[]> {
  const rows = await db().memory.findMany({ where: { userId, pinned: false }, select: { id: true } });
  if (!rows.length) return [];
  await db().memory.deleteMany({ where: { userId, pinned: false, id: { in: rows.map((r) => r.id) } } });
  return rows.map((r) => r.id);
}

// ---- retrieval --------------------------------------------------------------------

export type Similar = ExistingMemory & { sim: number };

/** The user's memories closest to [vec] by cosine similarity (HNSW index). */
export async function similarMemories(userId: string, vec: number[], k: number): Promise<Similar[]> {
  const v = toVector(vec);
  const c = await userCrypto(userId);
  const rows = await db().$queryRaw<Array<{ id: string; text: string; kind: string; pinned: boolean; slot: string | null; slot_enc: string | null; sim: number }>>`
    SELECT id, text, kind, pinned, slot, slot_enc, 1 - (embedding <=> ${v}::vector) AS sim
    FROM memories
    WHERE user_id = ${userId}::uuid AND embedding IS NOT NULL
    ORDER BY embedding <=> ${v}::vector
    LIMIT ${k}`;
  return rows.map((r) => {
    const m = openMem(c, { text: r.text, slot: r.slot, slotEnc: r.slot_enc });
    return { id: r.id, text: m.text, kind: r.kind as Kind, pinned: r.pinned, slot: m.slot, sim: Number(r.sim) };
  });
}

const BRIEF = { id: true, text: true, kind: true, pinned: true, slot: true, slotEnc: true } as const;
type BriefRow = { id: string; text: string; kind: string; pinned: boolean; slot: string | null; slotEnc: string | null };
const asExisting = (c: UserCrypto, r: BriefRow): ExistingMemory => {
  const m = openMem(c, r);
  return { id: m.id, text: m.text, kind: m.kind as Kind, pinned: m.pinned, slot: m.slot };
};

export async function pinnedMemories(userId: string, limit = 10): Promise<ExistingMemory[]> {
  const rows = await db().memory.findMany({ where: { userId, pinned: true }, select: BRIEF, orderBy: { updatedAt: "desc" }, take: limit });
  const c = await userCrypto(userId);
  return rows.map((r) => asExisting(c, r));
}

export async function recentMemories(userId: string, limit: number): Promise<ExistingMemory[]> {
  const rows = await db().memory.findMany({ where: { userId }, select: BRIEF, orderBy: { updatedAt: "desc" }, take: limit });
  const c = await userCrypto(userId);
  return rows.map((r) => asExisting(c, r));
}

/** The user's memories holding any of [slots] (indexed lookup, no embedding). */
export async function slotMemories(userId: string, slots: string[]): Promise<ExistingMemory[]> {
  if (!slots.length) return [];
  const c = await userCrypto(userId);
  // Hashed slots (current rows) and the plain names (rows written before encryption) are both looked up.
  const wanted = [...new Set([...slots.map((s) => c.blindIndex(T, "slot", s)), ...slots])];
  const rows = await db().memory.findMany({ where: { userId, slot: { in: wanted } }, select: BRIEF });
  return rows.map((r) => asExisting(c, r));
}

/** The user's newest memories of one kind. */
export async function kindMemories(userId: string, kind: Kind, limit: number): Promise<ExistingMemory[]> {
  const rows = await db().memory.findMany({ where: { userId, kind }, select: BRIEF, orderBy: { updatedAt: "desc" }, take: limit });
  const c = await userCrypto(userId);
  return rows.map((r) => asExisting(c, r));
}

/** Who the user is (name, location, work, ...): small, so it is injected on every turn. */
export const identityMemories = (userId: string, limit = 6) => kindMemories(userId, "identity", limit);

export async function touchMemories(userId: string, ids: string[]): Promise<void> {
  if (!ids.length) return;
  // Raw SQL on purpose: Prisma's @updatedAt would also bump updated_at (the list order).
  await db().$executeRaw`UPDATE memories SET last_used_at = now() WHERE user_id = ${userId}::uuid AND id = ANY(${ids}::uuid[])`;
}
