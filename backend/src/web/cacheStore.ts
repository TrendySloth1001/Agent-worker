// Persistent L2 for the web-search cache (Postgres, shared by all users). The
// in-memory LRU stays in front; this survives restarts and is shared by
// round-table seats and every user. Every failure reads as a miss.
import { db, isDbUp } from "../db/prisma.js";
import { log } from "../util/logger.js";
import type { Candidate, Freshness } from "./types.js";

/** Cache identity: provider, freshness class and the query with case, punctuation and spacing removed. */
export function searchCacheKey(provider: string, fresh: Freshness, query: string): string {
  const q = query.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
  return `${provider}|${fresh}|${q}`.slice(0, 400);
}

let lastPurge = 0;

export async function readPersisted(key: string): Promise<Candidate[] | null> {
  if (!isDbUp()) return null;
  try {
    const row = await db().webCache.findUnique({ where: { key } });
    if (!row || row.expiresAt.getTime() <= Date.now()) return null;
    return Array.isArray(row.payload) ? (row.payload as unknown as Candidate[]) : null;
  } catch (e) {
    log.warn("web cache read failed", { message: (e as Error).message?.slice(0, 100) });
    return null;
  }
}

/** Fire-and-forget; also purges expired rows now and then. */
export function writePersisted(key: string, candidates: Candidate[], ttlMs: number): void {
  if (!isDbUp()) return;
  const expiresAt = new Date(Date.now() + ttlMs);
  const payload = candidates as unknown as object;
  void db()
    .webCache.upsert({ where: { key }, create: { key, payload, expiresAt }, update: { payload, expiresAt } })
    .then(async () => {
      if (Date.now() - lastPurge < 10 * 60_000) return;
      lastPurge = Date.now();
      await db().webCache.deleteMany({ where: { expiresAt: { lt: new Date() } } });
    })
    .catch((e) => log.warn("web cache write failed", { message: (e as Error).message?.slice(0, 100) }));
}
