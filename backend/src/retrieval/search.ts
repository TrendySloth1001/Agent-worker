import { getEmbeddingGuardError } from "../db/embeddingGuard.js";
import { db, isDbUp, Prisma, tx } from "../db/prisma.js";
import { toVector } from "../db/vector.js";
import { embedTexts } from "../embeddings/index.js";
import { config } from "../config.js";
import { AppError } from "../util/errors.js";
import { ownerFilter } from "../auth/context.js";

export type KbHit = { chunkId: number; score: number; title: string; url: string; headingPath: string | null; content: string; sourceType: string; site: string };

const CANDIDATES = 24;
const RRF_K = 60;
const MAX_PER_DOC = 2;
const KW_ONLY_FLOOR = 0.2; // a keyword match below the similarity floor still needs minimal semantic relevance
const TOKEN_BUDGET = 3000;

type Row = { id: bigint; sim: number; doc_id: string; title: string | null; url: string; heading_path: string | null; content: string; token_count: number | null; type: string };

// The similarity and keyword searches stay raw SQL: pgvector's <=> operator
// (served by the HNSW index) and Postgres full-text search have no Prisma API.
const COLS = Prisma.sql`c.id, c.document_id AS doc_id, c.heading_path, c.content, c.token_count, d.title, d.url, s.type`;
const JOINS = Prisma.sql`FROM chunks c JOIN documents d ON d.id = c.document_id JOIN sources s ON s.id = c.source_id`;

function keywordQuery(q: string): string {
  const words = [...new Set(q.toLowerCase().match(/[\p{L}\p{N}_#+.-]{3,}/gu) ?? [])]
    .map((w) => w.replace(/^[.+-]+|[.+-]+$/g, ""))
    .filter((w) => w.length >= 3)
    .slice(0, 12);
  return words.join(" or ");
}

function hostOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
}

export async function retrieve(queryText: string, opts: { k?: number; sourceIds?: string[] } = {}): Promise<KbHit[]> {
  const k = Math.min(Math.max(opts.k ?? config.ragTopK, 1), 20);
  const text = queryText.trim().slice(0, 2000);
  if (!text) return [];
  if (!isDbUp()) throw new AppError(503, "unavailable", "Knowledge base unavailable (database down)", true);
  const guard = getEmbeddingGuardError();
  if (guard) throw new AppError(503, "unavailable", guard);

  const filter = opts.sourceIds?.length ? opts.sourceIds : null;
  // Only the caller's own knowledge base.
  const [unscoped, uid] = ownerFilter();
  const any = await db().chunk.findFirst({
    where: { ...(filter ? { sourceId: { in: filter } } : {}), ...(unscoped ? {} : { source: { userId: uid } }) },
    select: { id: true },
  });
  if (!any) return [];

  const [qv] = await embedTexts([text], "query");
  const vec = toVector(qv);
  const kw = keywordQuery(text);
  // Same filters as above, as SQL: optional source list, only the caller's own knowledge base.
  const inSources = filter ? Prisma.sql`AND c.source_id IN (${Prisma.join(filter.map((id) => Prisma.sql`${id}::uuid`))})` : Prisma.empty;
  const mine = unscoped ? Prisma.empty : Prisma.sql`AND s.user_id IS NOT DISTINCT FROM ${uid}::uuid`;

  const { vecRows, kwRows } = await tx(async (c) => {
    await c.$executeRaw`SET LOCAL hnsw.ef_search = 40`;
    // Keep scanning the index until enough rows pass the per-user filter.
    await c.$executeRaw`SET LOCAL hnsw.iterative_scan = relaxed_order`;
    const v = await c.$queryRaw<Row[]>`
      SELECT ${COLS}, 1 - (c.embedding <=> ${vec}::vector) AS sim ${JOINS}
      WHERE true ${inSources} ${mine}
      ORDER BY c.embedding <=> ${vec}::vector LIMIT ${CANDIDATES}`;
    let kRows: Row[] = [];
    if (kw) {
      kRows = await c.$queryRaw<Row[]>`
        SELECT ${COLS}, 1 - (c.embedding <=> ${vec}::vector) AS sim ${JOINS}
        WHERE c.tsv @@ websearch_to_tsquery('english', ${kw}) ${inSources} ${mine}
        ORDER BY ts_rank_cd(c.tsv, websearch_to_tsquery('english', ${kw})) DESC LIMIT ${CANDIDATES}`;
    }
    return { vecRows: v, kwRows: kRows };
  });

  const byId = new Map<bigint, Row & { rrf: number; kw: boolean }>();
  const add = (rows: Row[], isKw: boolean) =>
    rows.forEach((r, i) => {
      const e = byId.get(r.id) ?? { ...r, sim: Number(r.sim), rrf: 0, kw: false };
      e.rrf += 1 / (RRF_K + i + 1);
      if (isKw) e.kw = true;
      byId.set(r.id, e);
    });
  add(vecRows, false);
  add(kwRows, true);

  const ranked = [...byId.values()].filter((r) => r.sim >= config.ragMinSim || (r.kw && r.sim >= KW_ONLY_FLOOR)).sort((a, b) => b.rrf - a.rrf);
  const perDoc = new Map<string, number>();
  const out: KbHit[] = [];
  let tokens = 0;
  for (const r of ranked) {
    if (out.length >= k) break;
    if ((perDoc.get(r.doc_id) ?? 0) >= MAX_PER_DOC) continue;
    const t = r.token_count ?? Math.ceil(r.content.length / 4);
    if (out.length > 0 && tokens + t > TOKEN_BUDGET) continue;
    perDoc.set(r.doc_id, (perDoc.get(r.doc_id) ?? 0) + 1);
    tokens += t;
    out.push({
      chunkId: Number(r.id),
      score: Math.round(r.sim * 1000) / 1000,
      title: r.title ?? hostOf(r.url),
      url: r.url,
      headingPath: r.heading_path,
      content: r.content,
      sourceType: r.type,
      site: r.type === "note" ? "note" : hostOf(r.url),
    });
  }
  return out;
}

export async function kbStats(): Promise<{ sources: number; chunks: number } | null> {
  if (!isDbUp()) return null;
  try {
    const [unscoped, uid] = ownerFilter();
    const mine = unscoped ? {} : { userId: uid };
    const [sources, chunks] = await db().$transaction([db().source.count({ where: mine }), db().chunk.count({ where: { source: mine } })]);
    return { sources, chunks };
  } catch {
    return null;
  }
}
