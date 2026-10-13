import { db } from "../db/prisma.js";
import { currentUser } from "../auth/context.js";
import { decryptSecret } from "../connections/crypto.js";
import { log } from "../util/logger.js";
import { Slots, SLOT_SIZES } from "../llm/slots.js";
import type { ProviderId } from "../models.js";

/**
 * Per-user provider keys: storage, an in-memory cache of the decrypted keys of
 * recently active users, and the lookup the LLM router uses. A user's key is
 * only ever returned for that user's own request (keyed by currentUser()).
 */

export type KeyStatus = "untested" | "valid" | "invalid" | "quota";

export type KeyRow = {
  userId: string;
  provider: string;
  label: string;
  keyEnc: string;
  keyHint: string;
  status: KeyStatus;
  lastCheckedAt: Date | null;
  createdAt: Date;
};

/** Storage seam: Prisma in production, swapped in tests. */
export interface KeyRepo {
  list(userId: string): Promise<KeyRow[]>;
  get(userId: string, provider: string): Promise<KeyRow | null>;
  upsert(row: { userId: string; provider: string; label: string; keyEnc: string; keyHint: string }): Promise<KeyRow>;
  setStatus(userId: string, provider: string, status: KeyStatus, at: Date): Promise<void>;
  remove(userId: string, provider: string): Promise<boolean>;
}

const toRow = (r: { userId: string; provider: string; label: string; keyEnc: string; keyHint: string; status: string; lastCheckedAt: Date | null; createdAt: Date }): KeyRow => ({ ...r, status: r.status as KeyStatus });

export const prismaRepo: KeyRepo = {
  async list(userId) {
    return (await db().userApiKey.findMany({ where: { userId }, orderBy: { createdAt: "asc" } })).map(toRow);
  },
  async get(userId, provider) {
    const r = await db().userApiKey.findUnique({ where: { userId_provider: { userId, provider } } });
    return r ? toRow(r) : null;
  },
  async upsert(row) {
    const data = { label: row.label, keyEnc: row.keyEnc, keyHint: row.keyHint, status: "untested", lastCheckedAt: null };
    return toRow(await db().userApiKey.upsert({ where: { userId_provider: { userId: row.userId, provider: row.provider } }, create: { userId: row.userId, provider: row.provider, ...data }, update: data }));
  },
  async setStatus(userId, provider, status, at) {
    await db().userApiKey.updateMany({ where: { userId, provider }, data: { status, lastCheckedAt: at } });
  },
  async remove(userId, provider) {
    return (await db().userApiKey.deleteMany({ where: { userId, provider } })).count > 0;
  },
};

let repo: KeyRepo = prismaRepo;
/** Test hook. */
export function setKeyRepo(r: KeyRepo | null): void {
  repo = r ?? prismaRepo;
  cache.clear();
}
export const keyRepo = (): KeyRepo => repo;

// ---- cache of decrypted keys ---------------------------------------------------

type Cached = { key: string; status: KeyStatus; checkedAt: number };
type Entry = { at: number; keys: Map<string, Cached> };
const cache = new Map<string, Entry>();
const CACHE_TTL_MS = 60_000;
/** A key that ran out of credit is tried again after this long (a top-up needs no manual re-test). */
export const QUOTA_RETRY_MS = 30 * 60_000;
const MAX_CACHED_USERS = 500;

let clock = () => Date.now();
export const setKeyClock = (fn: (() => number) | null): void => {
  clock = fn ?? (() => Date.now());
};

function decrypt(row: KeyRow): Cached | null {
  try {
    return { key: decryptSecret(row.keyEnc), status: row.status, checkedAt: row.lastCheckedAt?.getTime() ?? 0 };
  } catch {
    log.warn("user api key could not be decrypted", { provider: row.provider });
    return null;
  }
}

/** Loads (or refreshes) the current user's keys into the cache. Never throws. */
export async function primeUserKeys(userId = currentUser()?.id ?? null): Promise<void> {
  if (!userId) return;
  const hit = cache.get(userId);
  if (hit && clock() - hit.at < CACHE_TTL_MS) return;
  try {
    const keys = new Map<string, Cached>();
    for (const row of await repo.list(userId)) {
      const c = decrypt(row);
      if (c) keys.set(row.provider, c);
    }
    if (cache.size >= MAX_CACHED_USERS) cache.delete(cache.keys().next().value!);
    cache.set(userId, { at: clock(), keys });
  } catch {
    // Database down or no CONNECTIONS_KEY: this request simply uses the server keys.
  }
}

/** Express middleware: loads the signed-in user's keys once per request. */
export function primeKeysMiddleware(_req: unknown, _res: unknown, next: () => void): void {
  void primeUserKeys().finally(next);
}

/** Puts a key straight into the cache (after a save or a status change). */
export function cacheKey(userId: string, provider: string, c: Cached | null): void {
  const e = cache.get(userId) ?? { at: 0, keys: new Map<string, Cached>() };
  if (c) e.keys.set(provider, c);
  else e.keys.delete(provider);
  cache.set(userId, e);
}

export const dropCached = (userId: string): void => void cache.delete(userId);

/** The key the current request must use for [provider], or null for the server's key. */
export function activeUserKey(provider: string, userId = currentUser()?.id ?? null): { key: string; userId: string } | null {
  if (!userId) return null;
  const c = cache.get(userId)?.keys.get(provider);
  if (!c) return null;
  if (c.status === "valid") return { key: c.key, userId };
  if (c.status === "quota" && clock() - c.checkedAt > QUOTA_RETRY_MS) return { key: c.key, userId };
  return null;
}

/**
 * The user's key stopped working mid-use: remember it (cache now, database in
 * the background) so the next call falls back to the server key instead of
 * hammering a dead key. Only `invalid` and `quota` are recorded.
 */
export function noteKeyFailure(userId: string, provider: string, status: "invalid" | "quota"): void {
  const now = new Date(clock());
  const c = cache.get(userId)?.keys.get(provider);
  if (c) {
    c.status = status;
    c.checkedAt = now.getTime();
  }
  void repo.setStatus(userId, provider, status, now).catch(() => {});
}

/** A key that just worked again after being marked down. */
export function noteKeyWorked(userId: string, provider: string): void {
  const c = cache.get(userId)?.keys.get(provider);
  if (!c || c.status === "valid") return;
  c.status = "valid";
  c.checkedAt = clock();
  void repo.setStatus(userId, provider, "valid", new Date(c.checkedAt)).catch(() => {});
}

// ---- per-user cooldowns and concurrency ---------------------------------------

const cooldowns = new Map<string, number>();
export function setUserCooldown(userId: string, modelId: string, ms: number): void {
  cooldowns.set(`${userId}|${modelId}`, clock() + ms);
}
export function userCooldownUntil(userId: string, modelId: string): number | null {
  const k = `${userId}|${modelId}`;
  const until = cooldowns.get(k);
  if (!until) return null;
  if (until <= clock()) {
    cooldowns.delete(k);
    return null;
  }
  return until;
}

const userSlots = new Map<string, Slots>();
/** A concurrency pool of the user's own: their key's capacity is theirs, not the shared server pool. */
export function slotsForUserKey(userId: string, provider: string): Slots {
  const k = `${userId}|${provider}`;
  let s = userSlots.get(k);
  if (!s) {
    s = new Slots(SLOT_SIZES[provider as ProviderId] ?? 2);
    userSlots.set(k, s);
  }
  return s;
}

/** True when the current request uses the user's own key for [provider]. */
export const usesUserKey = (provider: string): boolean => activeUserKey(provider) !== null;
