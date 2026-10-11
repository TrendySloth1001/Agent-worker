import { getEmbeddingGuardError } from "../db/migrate.js";
import { isDbUp, query, withTx } from "../db/pool.js";
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

type Row = { id: number; sim: number; doc_id: string; title: string | null; url: string; heading_path: string | null; content: string; token_count: number | null; type: string };

const COLS = `c.id, c.document_id AS doc_id, c.heading_path, c.content, c.token_count, d.title, d.url, s.type`;
const JOINS = `FROM chunks c JOIN documents d ON d.id = c.document_id JOIN sources s ON s.id = c.source_id`;

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
  const mine = "($4::boolean OR s.user_id IS NOT DISTINCT FROM $5::uuid)";
  const any = await query(
    `SELECT 1 FROM chunks c JOIN sources s ON s.id = c.source_id
      WHERE ($1::uuid[] IS NULL OR c.source_id = ANY($1::uuid[])) AND ($2::boolean OR s.user_id IS NOT DISTINCT FROM $3::uuid) LIMIT 1`,
    [filter, unscoped, uid],
  );
  if (any.rowCount === 0) return [];

  const [qv] = await embedTexts([text], "query");
  const vec = `[${qv.join(",")}]`;
  const kw = keywordQuery(text);

  const { vecRows, kwRows } = await withTx(async (c) => {
    await c.query("SET LOCAL hnsw.ef_search = 40");
    // Keep scanning the index until enough rows pass the per-user filter.
    await c.query("SET LOCAL hnsw.iterative_scan = relaxed_order");
    const v = await c.query<Row>(
      `SELECT ${COLS}, 1 - (c.embedding <=> $1::vector) AS sim ${JOINS}
       WHERE ($2::uuid[] IS NULL OR c.source_id = ANY($2::uuid[])) AND ($3::boolean OR s.user_id IS NOT DISTINCT FROM $4::uuid)
       ORDER BY c.embedding <=> $1::vector LIMIT ${CANDIDATES}`,
      [vec, filter, unscoped, uid],
    );
    let kRows: Row[] = [];
    if (kw) {
      const r = await c.query<Row>(
        `SELECT ${COLS}, 1 - (c.embedding <=> $1::vector) AS sim ${JOINS}
         WHERE c.tsv @@ websearch_to_tsquery('english', $3) AND ($2::uuid[] IS NULL OR c.source_id = ANY($2::uuid[])) AND ${mine}
         ORDER BY ts_rank_cd(c.tsv, websearch_to_tsquery('english', $3)) DESC LIMIT ${CANDIDATES}`,
        [vec, filter, kw, unscoped, uid],
      );
      kRows = r.rows;
    }
    return { vecRows: v.rows, kwRows: kRows };
  });

  const byId = new Map<number, Row & { rrf: number; kw: boolean }>();
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
    const r = await query(
      `SELECT (SELECT count(*)::int FROM sources WHERE $1::boolean OR user_id IS NOT DISTINCT FROM $2::uuid) AS s,
              (SELECT count(*)::int FROM chunks c JOIN sources x ON x.id = c.source_id WHERE $1::boolean OR x.user_id IS NOT DISTINCT FROM $2::uuid) AS c`,
      [unscoped, uid],
    );
    return { sources: r.rows[0].s, chunks: r.rows[0].c };
  } catch {
    return null;
  }
}
