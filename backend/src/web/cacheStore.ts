// Persistent L2 for the web-search cache (Postgres, shared by all users). The
// in-memory LRU stays in front; this survives restarts and is shared by
// round-table seats and every user. Every failure reads as a miss.
// Also holds read pages ("page|<url>") so a popular page is fetched once.
import { createHash } from "node:crypto";
import { db, isDbUp } from "../db/prisma.js";
import { log } from "../util/logger.js";
import type { Candidate, Freshness } from "./types.js";

/** Query text as a cache identity: case, punctuation, quotes and spacing removed. */
export const normalizeQuery = (query: string) => query.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();

const STOP = new Set(["a", "an", "the", "of", "in", "on", "at", "to", "for", "is", "are", "was", "were", "and", "or", "do", "does", "did", "what", "whats", "who", "how", "me", "about", "please", "tell"]);

/** The meaningful words of a query (no stop words), as a set: the basis of near-same query matching. */
export const queryTerms = (query: string): Set<string> => new Set(normalizeQuery(query).split(" ").filter((t) => t && !STOP.has(t)));

/** Word-order and filler independent query identity: "the price of X" and "X price" share a cache entry. */
export function queryIdentity(query: string): string {
  const t = [...queryTerms(query)].sort();
  return t.length ? t.join(" ") : normalizeQuery(query);
}

/** Jaccard similarity of two term sets. */
export function termOverlap(a: Set<string>, b: Set<string>): number {
  if (!a.size || !b.size) return 0;
  let n = 0;
  for (const t of a) if (b.has(t)) n++;
  return n / (a.size + b.size - n);
}

/** Cache identity: provider, freshness class, language and the query's identity (hashed before it is stored). */
export function searchCacheKey(provider: string, fresh: Freshness, query: string, lang?: string, region?: string): string {
  return `${provider}|${fresh}${lang && lang !== "en" ? `|${lang}` : ""}${region ? `|r:${region}` : ""}|${queryIdentity(query)}`.slice(0, 400);
}

let lastPurge = 0;

/**
 * Rows are stored under a hash of the cache identity: the identity holds what users searched for and which pages they
 * opened, and this table is shared by everyone. The payload is public web data (results, page text), not user content.
 */
export const storedKey = (key: string) => `h:${createHash("sha256").update(key).digest("hex").slice(0, 40)}`;

export async function readPersistedValue<T>(key: string, valid: (v: unknown) => v is T): Promise<T | null> {
  if (!isDbUp()) return null;
  try {
    const row = await db().webCache.findUnique({ where: { key: storedKey(key) } });
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
  const id = storedKey(key);
  void db()
    .webCache.upsert({ where: { key: id }, create: { key: id, payload, expiresAt }, update: { payload, expiresAt } })
    .then(async () => {
      if (Date.now() - lastPurge < 10 * 60_000) return;
      lastPurge = Date.now();
      await db().webCache.deleteMany({ where: { expiresAt: { lt: new Date() } } });
    })
    .catch((e) => log.warn("web cache write failed", { message: (e as Error).message?.slice(0, 100) }));
}
