// Persistent L2 for the web-search cache (Postgres, shared by all users). The
// in-memory LRU stays in front; this survives restarts and is shared by
// round-table seats and every user. Every failure reads as a miss.
// Also holds read pages ("page|<url>") so a popular page is fetched once.
import { db, isDbUp } from "../db/prisma.js";
import { log } from "../util/logger.js";
import type { Candidate, Freshness } from "./types.js";

/** Query text as a cache identity: case, punctuation, quotes and spacing removed. */
export const normalizeQuery = (query: string) => query.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();

/** Cache identity: provider, freshness class, language and the normalized query. */
export function searchCacheKey(provider: string, fresh: Freshness, query: string, lang?: string): string {
  return `${provider}|${fresh}${lang && lang !== "en" ? `|${lang}` : ""}|${normalizeQuery(query)}`.slice(0, 400);
}

let lastPurge = 0;

export async function readPersistedValue<T>(key: string, valid: (v: unknown) => v is T): Promise<T | null> {
  if (!isDbUp()) return null;
  try {
    const row = await db().webCache.findUnique({ where: { key } });
    if (!row || row.expiresAt.getTime() <= Date.now()) return null;
    return valid(row.payload) ? row.payload : null;
  } catch (e) {
    log.warn("web cache read failed", { message: (e as Error).message?.slice(0, 100) });
    return null;
  }
}

export function readPersisted(key: string): Promise<Candidate[] | null> {
  return readPersistedValue(key, (v): v is Candidate[] => Array.isArray(v));
}

/** Fire-and-forget; also purges expired rows now and then. */
export function writePersisted(key: string, value: unknown, ttlMs: number): void {
  if (!isDbUp()) return;
  const expiresAt = new Date(Date.now() + ttlMs);
  const payload = value as object;
  void db()
    .webCache.upsert({ where: { key }, create: { key, payload, expiresAt }, update: { payload, expiresAt } })
    .then(async () => {
      if (Date.now() - lastPurge < 10 * 60_000) return;
      lastPurge = Date.now();
      await db().webCache.deleteMany({ where: { expiresAt: { lt: new Date() } } });
    })
    .catch((e) => log.warn("web cache write failed", { message: (e as Error).message?.slice(0, 100) }));
}
