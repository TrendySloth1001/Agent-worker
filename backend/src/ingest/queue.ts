import pLimit from "p-limit";
import { query, withTx, onDbUp, isDbUp } from "../db/pool.js";
import { embedTexts } from "../embeddings/index.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { chunkMarkdown, embeddingInput, sha, type Chunk } from "./chunk.js";
import { connectors } from "./connectors/index.js";
import type { DocInput, IngestCtx } from "./types.js";

const limit = pLimit(1);
const queued = new Set<string>();

export function enqueue(sourceId: string): void {
  if (queued.has(sourceId)) return;
  queued.add(sourceId);
  void limit(() => runSource(sourceId)).finally(() => queued.delete(sourceId));
}

/** On boot / DB recovery: running -> queued, then enqueue everything queued. */
export function recoverQueue(): void {
  void (async () => {
    try {
      await query("UPDATE sources SET status='queued', updated_at=now() WHERE status='running'");
      const { rows } = await query<{ id: string }>("SELECT id FROM sources WHERE status='queued' ORDER BY created_at");
      for (const r of rows) enqueue(r.id);
      if (rows.length) log.info("ingestion recovered", { queued: rows.length });
    } catch (e) {
      log.warn("queue recovery failed", { reason: (e as Error).message.slice(0, 120) });
    }
  })();
}
onDbUp(recoverQueue);

const vec = (v: number[]) => `[${v.join(",")}]`;
const errText = (e: unknown) => (e instanceof Error ? e.message : String(e)).slice(0, 200);

type Pending = { doc: DocInput; hash: string; chunks: Chunk[]; reuse: Map<string, string>; need: number[] };

async function runSource(id: string): Promise<void> {
  if (!isDbUp()) return;
  const { rows } = await query("SELECT id, type, uri, options FROM sources WHERE id=$1", [id]);
  const src = rows[0];
  if (!src) return;
  const connector = connectors[src.type as keyof typeof connectors];
  const lim: number = Math.min(Math.max(Number(src.options?.limit) || 20, 1), 100);
  await query("UPDATE sources SET status='running', error=NULL, progress_done=0, progress_total=NULL, updated_at=now() WHERE id=$1", [id]);

  let done = 0;
  let total: number | null = null;
  let stored = 0;
  let firstError: string | null = null;
  const seen = new Set<string>();
  let pending: Pending[] = [];
  let pendingTexts = 0;
  let progressTimer = 0;

  const saveProgress = async (force = false) => {
    const now = Date.now();
    if (!force && now - progressTimer < 500) return;
    progressTimer = now;
    await query("UPDATE sources SET progress_done=$2, progress_total=$3, updated_at=now() WHERE id=$1", [id, done, total]).catch(() => {});
  };

  const flush = async () => {
    const batch = pending;
    pending = [];
    pendingTexts = 0;
    if (!batch.length) return;
    const texts: string[] = [];
    const slots: Array<[number, number]> = [];
    batch.forEach((p, bi) => p.need.forEach((ci) => (texts.push(embeddingInput(p.chunks[ci])), slots.push([bi, ci]))));
    const embs = texts.length ? await embedTexts(texts, "document") : [];
    const fresh = new Map<string, string>();
    slots.forEach(([bi, ci], i) => fresh.set(`${bi}:${ci}`, vec(embs[i])));
    for (let bi = 0; bi < batch.length; bi++) {
      const p = batch[bi];
      await storeDoc(id, p, (ci) => fresh.get(`${bi}:${ci}`) ?? p.reuse.get(p.chunks[ci].hash)!);
      stored++;
      done++;
      await saveProgress();
    }
  };

  const ctx: IngestCtx = {
    limit: lim,
    setTotal: (n) => {
      total = n;
      void saveProgress(true);
    },
    setTitle: (t) => {
      void query("UPDATE sources SET title=COALESCE(title,$2) WHERE id=$1", [id, t.slice(0, 200)]).catch(() => {});
    },
    skip: (reason) => {
      done++;
      if (reason && !firstError) firstError = reason;
      void saveProgress();
    },
    emit: async (doc) => {
      if (seen.has(doc.url)) return;
      seen.add(doc.url);
      const markdown = doc.markdown.replace(/\u0000/g, "").trim();
      if (markdown.length < 20) {
        done++;
        return;
      }
      const hash = sha(markdown);
      const existing = (await query("SELECT id, content_hash FROM documents WHERE source_id=$1 AND url=$2", [id, doc.url])).rows[0];
      if (existing?.content_hash === hash) {
        done++; // unchanged: keep chunks and embeddings
        await saveProgress();
        return;
      }
      const chunks = chunkMarkdown(markdown, doc.title);
      if (!chunks.length) {
        done++;
        return;
      }
      const reuse = new Map<string, string>();
      if (existing) {
        const old = await query<{ content_hash: string; emb: string }>("SELECT content_hash, embedding::text AS emb FROM chunks WHERE document_id=$1", [existing.id]);
        for (const r of old.rows) reuse.set(r.content_hash, r.emb);
      }
      const need = chunks.map((c, i) => (reuse.has(c.hash) ? -1 : i)).filter((i) => i >= 0);
      pending.push({ doc: { ...doc, markdown }, hash, chunks, reuse, need });
      pendingTexts += need.length;
      if (pendingTexts >= 48 || pending.length >= 10) await flush();
    },
  };

  try {
    await connector.run({ id, type: src.type, uri: src.uri, options: src.options ?? {} }, ctx);
    await flush();
    if (stored === 0 && done > 0 && firstError && seen.size === 0) throw new AppError(502, "upstream_failed", firstError);
    // refresh semantics: drop documents that no longer exist upstream (only after a fully successful run)
    if (seen.size > 0) await query("DELETE FROM documents WHERE source_id=$1 AND NOT (url = ANY($2::text[]))", [id, [...seen]]);
    const counts = await query(
      `SELECT (SELECT count(*)::int FROM documents WHERE source_id=$1) AS d, (SELECT count(*)::int FROM chunks WHERE source_id=$1) AS c`,
      [id],
    );
    if (counts.rows[0].c === 0) throw new AppError(502, "upstream_failed", firstError ?? "No content could be extracted from this source");
    await query(
      `UPDATE sources SET status='ready', error=NULL, doc_count=$2, chunk_count=$3, progress_done=$4, progress_total=$4, last_ingested_at=now(), updated_at=now() WHERE id=$1`,
      [id, counts.rows[0].d, counts.rows[0].c, Math.max(done, counts.rows[0].d)],
    );
    log.info("ingestion finished", { sourceId: id, type: src.type, docs: counts.rows[0].d, chunks: counts.rows[0].c });
  } catch (e) {
    log.warn("ingestion failed", { sourceId: id, reason: errText(e) });
    await query("UPDATE sources SET status='failed', error=$2, updated_at=now() WHERE id=$1", [id, errText(e)]).catch(() => {});
  }
}

async function storeDoc(sourceId: string, p: Pending, embFor: (ci: number) => string): Promise<void> {
  await withTx(async (c) => {
    const d = await c.query(
      `INSERT INTO documents (source_id, url, title, content_hash, meta) VALUES ($1,$2,$3,$4,$5)
       ON CONFLICT (source_id, url) DO UPDATE SET title=EXCLUDED.title, content_hash=EXCLUDED.content_hash, meta=EXCLUDED.meta
       RETURNING id`,
      [sourceId, p.doc.url, p.doc.title?.slice(0, 300) ?? null, p.hash, JSON.stringify(p.doc.meta ?? {})],
    );
    const docId = d.rows[0].id as string;
    await c.query("DELETE FROM chunks WHERE document_id=$1", [docId]);
    const cols = 7;
    for (let i = 0; i < p.chunks.length; i += 50) {
      const part = p.chunks.slice(i, i + 50);
      const params: unknown[] = [];
      const values = part.map((ch, j) => {
        params.push(docId, sourceId, ch.ord, ch.headingPath, ch.content, ch.tokenCount, ch.hash);
        params.push(embFor(i + j));
        return `($${j * (cols + 1) + 1},$${j * (cols + 1) + 2},$${j * (cols + 1) + 3},$${j * (cols + 1) + 4},$${j * (cols + 1) + 5},$${j * (cols + 1) + 6},$${j * (cols + 1) + 7},$${j * (cols + 1) + 8}::vector)`;
      });
      await c.query(
        `INSERT INTO chunks (document_id, source_id, ord, heading_path, content, token_count, content_hash, embedding) VALUES ${values.join(",")}`,
        params,
      );
    }
  });
}
