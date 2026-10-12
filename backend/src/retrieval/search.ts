import { getEmbeddingGuardError } from "../db/embeddingGuard.js";
import { db, isDbUp, Prisma, tx } from "../db/prisma.js";
import { toVector } from "../db/vector.js";
import { embedQueries } from "../embeddings/index.js";
import { config } from "../config.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { ownerFilter } from "../auth/context.js";
import { joinOverlap, mmr, parseVector, rrfFuse } from "./fusion.js";
import { fuzzyTerms, needsFuzzy, synonymsOf } from "../nlp/text.js";
import { rerank } from "./rerank.js";
import { rewriteQueries, type HistoryMsg } from "./rewrite.js";
import { extractEntities, quotableNames } from "../nlp/entities.js";

export type KbHit = {
  chunkId: number;
  score: number;
  title: string;
  url: string;
  headingPath: string | null;
  content: string;
  /** web | github | stackoverflow | reddit | hackernews | note | file | doc */
  sourceType: string;
  site: string;
  /** For doc hits: the generated doc and section the chunk came from. */
  docId?: string;
  sectionId?: string;
  /** For file hits: the uploaded file id. */
  fileId?: string;
};

export type RetrieveOpts = {
  k?: number;
  sourceIds?: string[];
  /** Recent conversation, used to turn a follow-up into standalone queries. */
  history?: HistoryMsg[];
  rewrite?: boolean;
  /** Query variants already resolved for this turn (src/context): skips the rewrite call. */
  rewrites?: string[];
  rerank?: boolean;
};

const CANDIDATES = 24; // per query and per search leg
const RRF_K = 60;
const POOL = 20; // fused candidates considered for rerank / MMR
const MAX_PER_DOC = 4;
const KW_ONLY_FLOOR = 0.2; // a keyword match below the similarity floor still needs minimal semantic relevance
const TOKEN_BUDGET = 4500;
const EXPAND_TOP = 3; // neighbour chunks are added around this many best hits
const REWRITE_WEIGHT = 0.8;

type Row = {
  id: bigint;
  sim: number;
  doc_id: string;
  ord: number;
  title: string | null;
  url: string;
  heading_path: string | null;
  content: string;
  token_count: number | null;
  type: string;
  meta: Record<string, unknown> | null;
};

// The similarity and keyword searches stay raw SQL: pgvector's <=> operator
// (served by the HNSW index) and Postgres full-text search have no Prisma API.
const COLS = Prisma.sql`c.id, c.document_id AS doc_id, c.ord, c.heading_path, c.content, c.token_count, d.title, d.url, d.meta, s.type`;
const JOINS = Prisma.sql`FROM chunks c JOIN documents d ON d.id = c.document_id JOIN sources s ON s.id = c.source_id`;

/** OR-joined keyword terms for websearch_to_tsquery (identifiers like `useState` or `c++` survive), plus tech synonyms (k8s/kubernetes). The 'english' tsvector config does the stemming. */
export function keywordQuery(q: string): string {
  const words = [...new Set(q.toLowerCase().match(/[\p{L}\p{N}_#+.-]{3,}/gu) ?? [])]
    .map((w) => w.replace(/^[.+-]+|[.+-]+$/g, ""))
    .filter((w) => w.length >= 3)
    .slice(0, 12);
  if (words.length === 0) return "";
  const syn = words.flatMap((w) => synonymsOf(w)).filter((s) => !/\s/.test(s));
  // Exact names (multi-word people/orgs/products, owner/repo) also match as phrases, which ranks chunks that contain them whole higher.
  const phrases = quotableNames(extractEntities(q))
    .map((n) => n.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim())
    .filter((p, i, a) => p.includes(" ") && a.indexOf(p) === i)
    .slice(0, 3)
    .map((p) => `"${p}"`);
  return [...new Set([...words, ...syn]), ...phrases].join(" or ");
}

function hostOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
}

function toHit(r: Row, content: string, score: number): KbHit {
  const meta = r.meta ?? {};
  const hit: KbHit = {
    chunkId: Number(r.id),
    score: Math.round(score * 1000) / 1000,
    title: r.title ?? hostOf(r.url),
    url: r.url,
    headingPath: r.heading_path,
    content,
    sourceType: r.type,
    site: r.type === "note" ? "note" : r.type === "doc" || r.type === "file" ? r.type : hostOf(r.url),
  };
  if (r.type === "doc") {
    hit.docId = String(meta.docId ?? "");
    hit.sectionId = String(meta.sectionId ?? "");
  } else if (r.type === "file") hit.fileId = String(meta.fileId ?? "");
  return hit;
}

export async function retrieve(queryText: string, opts: RetrieveOpts = {}): Promise<KbHit[]> {
  const t0 = Date.now();
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

  // Follow-ups are rewritten into standalone queries (time-boxed, never fatal).
  const doRewrite = opts.rewrite ?? config.ragRewrite;
  const rewrites = opts.rewrites ?? (doRewrite && opts.history?.length ? await rewriteQueries(text, opts.history) : []);
  const queries = [...new Set([text, ...rewrites])];
  const tRewrite = Date.now() - t0;

  const vecs = (await embedQueries(queries)).map(toVector);
  // Same filters as above, as SQL: optional source list, only the caller's own knowledge base.
  const inSources = filter ? Prisma.sql`AND c.source_id IN (${Prisma.join(filter.map((id) => Prisma.sql`${id}::uuid`))})` : Prisma.empty;
  const mine = unscoped ? Prisma.empty : Prisma.sql`AND s.user_id IS NOT DISTINCT FROM ${uid}::uuid`;

  type Leg = { rows: Row[]; weight: number; kw: boolean };
  const legs = await tx(async (c) => {
    await c.$executeRaw`SET LOCAL hnsw.ef_search = 60`;
    // Keep scanning the index until enough rows pass the per-user filter.
    await c.$executeRaw`SET LOCAL hnsw.iterative_scan = relaxed_order`;
    const out: Leg[] = [];
    for (let qi = 0; qi < queries.length; qi++) {
      const vec = vecs[qi];
      const weight = qi === 0 ? 1 : REWRITE_WEIGHT;
      const v = await c.$queryRaw<Row[]>`
        SELECT ${COLS}, 1 - (c.embedding <=> ${vec}::vector) AS sim ${JOINS}
        WHERE true ${inSources} ${mine}
        ORDER BY c.embedding <=> ${vec}::vector LIMIT ${CANDIDATES}`;
      out.push({ rows: v, weight, kw: false });
      const kw = keywordQuery(queries[qi]);
      if (kw) {
        const kr = await c.$queryRaw<Row[]>`
          SELECT ${COLS}, 1 - (c.embedding <=> ${vec}::vector) AS sim ${JOINS}
          WHERE c.tsv @@ websearch_to_tsquery('english', ${kw}) ${inSources} ${mine}
          ORDER BY ts_rank_cd(c.tsv, websearch_to_tsquery('english', ${kw})) DESC LIMIT ${CANDIDATES}`;
        out.push({ rows: kr, weight, kw: true });
        // Typo tolerance: too few keyword hits -> trigram word_similarity (`term <% content`, GIN-indexed).
        if (needsFuzzy(kr.length)) {
          const terms = fuzzyTerms(queries[qi], 3);
          if (terms.length) {
            const anyTerm = Prisma.join(terms.map((t) => Prisma.sql`${t} <% c.content`), " OR ");
            const fr = await c.$queryRaw<Row[]>`
              SELECT ${COLS}, 1 - (c.embedding <=> ${vec}::vector) AS sim ${JOINS}
              WHERE (${anyTerm}) ${inSources} ${mine}
              ORDER BY c.embedding <=> ${vec}::vector LIMIT ${CANDIDATES}`;
            out.push({ rows: fr, weight: weight * 0.7, kw: true });
          }
        }
      }
    }
    return out;
  });
  const tSearch = Date.now() - t0;

  // Hybrid fusion (Reciprocal Rank Fusion over every vector and keyword list).
  const rows = new Map<bigint, Row & { simMax: number; kw: boolean }>();
  for (const leg of legs) {
    for (const r of leg.rows) {
      const e = rows.get(r.id) ?? { ...r, simMax: 0, kw: false };
      e.simMax = Math.max(e.simMax, Number(r.sim));
      if (leg.kw) e.kw = true;
      rows.set(r.id, e);
    }
  }
  const fused = rrfFuse(
    legs.map((l) => ({ ids: l.rows.map((r) => r.id), weight: l.weight })),
    RRF_K,
  );
  const eligible = fused.filter((f) => {
    const r = rows.get(f.id)!;
    return r.simMax >= config.ragMinSim || (r.kw && r.simMax >= KW_ONLY_FLOOR);
  });
  let pool = eligible.slice(0, POOL);
  if (pool.length === 0) return [];

  // Optional LLM rerank of the pool, time-boxed inside rerank().
  const doRerank = opts.rerank ?? config.ragRerank;
  let rerankMs = 0;
  if (doRerank && pool.length > k) {
    const tr = Date.now();
    const order = await rerank(
      text,
      pool.map((f) => ({ id: f.id, text: `${rows.get(f.id)!.heading_path ?? ""} ${rows.get(f.id)!.content}` })),
    );
    rerankMs = Date.now() - tr;
    const rank = new Map(order.map((id, i) => [id, i]));
    // Blend: reranker order drives relevance, fusion score breaks ties.
    pool = pool.map((f, i) => ({ ...f, score: 1 / (1 + (rank.get(f.id) ?? i)) + f.score })).sort((a, b) => b.score - a.score);
  }

  // MMR: diversity among near-duplicates, with a per-document cap and a token budget.
  const vectors = await poolVectors(pool.map((f) => f.id));
  const order = mmr(
    pool.map((f) => ({ id: Number(f.id), relevance: f.score, vec: vectors.get(f.id) ?? null })),
    Math.min(pool.length, k * 2),
  );
  const perDoc = new Map<string, number>();
  const picked: Array<Row & { simMax: number }> = [];
  let tokens = 0;
  for (const id of order) {
    if (picked.length >= k) break;
    const r = rows.get(BigInt(id))!;
    if ((perDoc.get(r.doc_id) ?? 0) >= MAX_PER_DOC) continue;
    const t = r.token_count ?? Math.ceil(r.content.length / 4);
    if (picked.length > 0 && tokens + t > TOKEN_BUDGET) continue;
    perDoc.set(r.doc_id, (perDoc.get(r.doc_id) ?? 0) + 1);
    tokens += t;
    picked.push(r);
  }

  // Neighbour expansion: the chunks before and after the best hits, so an answer split across a chunk boundary is complete.
  const neighbours = await fetchNeighbours(picked.slice(0, EXPAND_TOP), new Set(picked.map((r) => r.id)));
  const out = picked.map((r, i) => {
    let content = r.content;
    if (i < EXPAND_TOP) {
      const prev = neighbours.get(`${r.doc_id}:${r.ord - 1}`);
      const next = neighbours.get(`${r.doc_id}:${r.ord + 1}`);
      const extra = (prev?.token ?? 0) + (next?.token ?? 0);
      if (tokens + extra <= TOKEN_BUDGET + 1500) {
        if (prev) content = joinOverlap(prev.content, content);
        if (next) content = joinOverlap(content, next.content);
        tokens += extra;
      }
    }
    return toHit(r, content, r.simMax);
  });

  log.info("kb retrieve", {
    queries: queries.length,
    pool: eligible.length,
    hits: out.length,
    rewriteMs: tRewrite,
    searchMs: tSearch - tRewrite,
    rerankMs,
    totalMs: Date.now() - t0,
  });
  return out;
}

/** Embeddings of the pool, for MMR (one indexed lookup by primary key). */
async function poolVectors(ids: bigint[]): Promise<Map<bigint, Float32Array>> {
  const out = new Map<bigint, Float32Array>();
  if (ids.length === 0) return out;
  try {
    // Raw: reads the vector column as its text form.
    const rows = await db().$queryRaw<Array<{ id: bigint; emb: string }>>`
      SELECT id, embedding::text AS emb FROM chunks WHERE id IN (${Prisma.join(ids)})`;
    for (const r of rows) out.set(r.id, parseVector(r.emb));
  } catch (e) {
    log.warn("mmr vectors unavailable", { message: (e as Error).message?.slice(0, 100) });
  }
  return out;
}

/** The chunks right before and after each hit, in the same document (the hits are already authorised). */
async function fetchNeighbours(hits: Array<{ doc_id: string; ord: number }>, selected: Set<bigint>): Promise<Map<string, { content: string; token: number }>> {
  const out = new Map<string, { content: string; token: number }>();
  if (hits.length === 0) return out;
  try {
    const pairs = hits.flatMap((h) => [h.ord - 1, h.ord + 1].filter((o) => o >= 0).map((o) => Prisma.sql`(${h.doc_id}::uuid, ${o}::int)`));
    const rows = await db().$queryRaw<Array<{ id: bigint; document_id: string; ord: number; content: string; token_count: number | null }>>`
      SELECT id, document_id, ord, content, token_count FROM chunks WHERE (document_id, ord) IN (${Prisma.join(pairs)})`;
    for (const r of rows) {
      if (selected.has(r.id)) continue; // already returned as a hit of its own
      out.set(`${r.document_id}:${r.ord}`, { content: r.content, token: r.token_count ?? Math.ceil(r.content.length / 4) });
    }
  } catch (e) {
    log.warn("neighbour expansion failed", { message: (e as Error).message?.slice(0, 100) });
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
