import { db, isDbUp, Prisma } from "../db/prisma.js";
import { toVector } from "../db/vector.js";
import { embedQueries } from "../embeddings/index.js";
import { ownerFilter } from "../auth/context.js";
import type { KbPeekHit } from "../toggles/suggest.js";

const PEEK_ROWS = 8;

/**
 * A cheap look at the user's knowledge base for the "suggest KB" check: the nearest chunks to the query (one HNSW
 * lookup on the query embedding the turn already computed or caches) as title + cosine similarity. No rewriting,
 * keyword legs or reranking; the real retrieval only runs if the user turns the KB on.
 * Returns `hasContent: false` when the user has no knowledge base at all.
 */
export async function peekKb(query: string): Promise<{ hits: KbPeekHit[]; hasContent: boolean }> {
  const text = query.trim().slice(0, 500);
  if (!text || !isDbUp()) return { hits: [], hasContent: false };
  const [unscoped, uid] = ownerFilter();
  const any = await db().chunk.findFirst({ where: unscoped ? {} : { source: { userId: uid } }, select: { id: true } });
  if (!any) return { hits: [], hasContent: false };
  const [vec] = (await embedQueries([text])).map(toVector);
  const mine = unscoped ? Prisma.empty : Prisma.sql`AND s.user_id IS NOT DISTINCT FROM ${uid}::uuid`;
  const rows = await db().$queryRaw<{ title: string | null; url: string; sim: number }[]>`
    SELECT d.title, d.url, 1 - (c.embedding <=> ${vec}::vector) AS sim
    FROM chunks c JOIN documents d ON d.id = c.document_id JOIN sources s ON s.id = c.source_id
    WHERE true ${mine}
    ORDER BY c.embedding <=> ${vec}::vector LIMIT ${PEEK_ROWS}`;
  return { hits: rows.map((r) => ({ title: r.title || r.url, sim: Number(r.sim) })), hasContent: true };
}
