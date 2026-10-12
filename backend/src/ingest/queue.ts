import pLimit from "p-limit";
import { db, isDbUp, onDbUp, Prisma, tx, withDb } from "../db/prisma.js";
import { toVector } from "../db/vector.js";
import { embedTexts } from "../embeddings/index.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { chunkMarkdown, embeddingInput, sha, type Chunk } from "./chunk.js";
import { connectors } from "./connectors/index.js";
import type { DocInput, IngestCtx } from "./types.js";

const limit = pLimit(1);
const queued = new Set<string>();
/** Sources enqueued again while their run was in flight (e.g. a doc edited mid-index): run once more after. */
const dirty = new Set<string>();

export function enqueue(sourceId: string): void {
  if (queued.has(sourceId)) {
    dirty.add(sourceId);
    return;
  }
  queued.add(sourceId);
  void limit(() => runSource(sourceId)).finally(() => {
    queued.delete(sourceId);
    if (dirty.delete(sourceId)) enqueue(sourceId);
  });
}

/** On boot / DB recovery: running -> queued, then enqueue everything queued. */
export function recoverQueue(): void {
  void (async () => {
    try {
      await db().source.updateMany({ where: { status: "running" }, data: { status: "queued", updatedAt: new Date() } });
      const rows = await db().source.findMany({ where: { status: "queued" }, orderBy: { createdAt: "asc" }, select: { id: true } });
      for (const r of rows) enqueue(r.id);
      if (rows.length) log.info("ingestion recovered", { queued: rows.length });
    } catch (e) {
      log.warn("queue recovery failed", { reason: (e as Error).message.slice(0, 120) });
    }
  })();
}
onDbUp(recoverQueue);

const vec = toVector;
const errText = (e: unknown) => (e instanceof Error ? e.message : String(e)).slice(0, 200);

type Pending = { doc: DocInput; hash: string; chunks: Chunk[]; reuse: Map<string, string>; need: number[] };

async function runSource(id: string): Promise<void> {
  if (!isDbUp()) return;
  const row = await db().source.findUnique({ where: { id }, select: { id: true, type: true, uri: true, options: true, userId: true } });
  if (!row) return;
  const src = { ...row, options: (row.options ?? {}) as Record<string, any> };
  const connector = connectors[src.type as keyof typeof connectors];
  if (!connector) return;
  const lim: number = Math.min(Math.max(Number(src.options?.limit) || 20, 1), 100);
  // updateMany throughout: the source may be deleted while it is being ingested.
  await db().source.updateMany({
    where: { id },
    data: { status: "running", error: null, progressDone: 0, progressTotal: null, updatedAt: new Date() },
  });

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
    await withDb((c) => c.source.updateMany({ where: { id }, data: { progressDone: done, progressTotal: total, updatedAt: new Date() } })).catch(() => {});
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
      void withDb((c) => c.source.updateMany({ where: { id, title: null }, data: { title: t.slice(0, 200) } })).catch(() => {});
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
      const existing = await db().document.findUnique({ where: { sourceId_url: { sourceId: id, url: doc.url } }, select: { id: true, contentHash: true } });
      if (existing?.contentHash === hash) {
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
        // Raw: reads the vector column (as its text form) to reuse unchanged chunks' embeddings.
        const old = await db().$queryRaw<Array<{ content_hash: string; emb: string }>>`
          SELECT content_hash, embedding::text AS emb FROM chunks WHERE document_id = ${existing.id}::uuid`;
        for (const r of old) reuse.set(r.content_hash, r.emb);
      }
      const need = chunks.map((c, i) => (reuse.has(c.hash) ? -1 : i)).filter((i) => i >= 0);
      pending.push({ doc: { ...doc, markdown }, hash, chunks, reuse, need });
      pendingTexts += need.length;
      if (pendingTexts >= 48 || pending.length >= 10) await flush();
    },
  };

  try {
    await connector.run({ id, type: src.type, uri: src.uri, options: src.options ?? {}, userId: src.userId }, ctx);
    await flush();
    if (stored === 0 && done > 0 && firstError && seen.size === 0) throw new AppError(502, "upstream_failed", firstError);
    // refresh semantics: drop documents that no longer exist upstream (only after a fully successful run)
    if (seen.size > 0) await db().document.deleteMany({ where: { sourceId: id, url: { notIn: [...seen] } } });
    const [docs, chunks] = await db().$transaction([db().document.count({ where: { sourceId: id } }), db().chunk.count({ where: { sourceId: id } })]);
    if (chunks === 0) throw new AppError(502, "upstream_failed", firstError ?? "No content could be extracted from this source");
    const now = new Date();
    const finished = Math.max(done, docs);
    await db().source.updateMany({
      where: { id },
      data: { status: "ready", error: null, docCount: docs, chunkCount: chunks, progressDone: finished, progressTotal: finished, lastIngestedAt: now, updatedAt: now },
    });
    log.info("ingestion finished", { sourceId: id, type: src.type, docs, chunks });
  } catch (e) {
    log.warn("ingestion failed", { sourceId: id, reason: errText(e) });
    await withDb((c) => c.source.updateMany({ where: { id }, data: { status: "failed", error: errText(e), updatedAt: new Date() } })).catch(() => {});
  }
}

async function storeDoc(sourceId: string, p: Pending, embFor: (ci: number) => string): Promise<void> {
  await tx(async (c) => {
    const doc = { title: p.doc.title?.slice(0, 300) ?? null, contentHash: p.hash, meta: (p.doc.meta ?? {}) as Prisma.InputJsonValue };
    const d = await c.document.upsert({
      where: { sourceId_url: { sourceId, url: p.doc.url } },
      create: { sourceId, url: p.doc.url, ...doc },
      update: doc,
      select: { id: true },
    });
    await c.chunk.deleteMany({ where: { documentId: d.id } });
    // Raw: chunks carry a vector column, which createMany cannot write. One multi-row INSERT per 50 chunks.
    for (let i = 0; i < p.chunks.length; i += 50) {
      const values = p.chunks.slice(i, i + 50).map(
        (ch, j) =>
          Prisma.sql`(${d.id}::uuid, ${sourceId}::uuid, ${ch.ord}, ${ch.headingPath}, ${ch.content}, ${ch.tokenCount}, ${ch.hash}, ${embFor(i + j)}::vector)`,
      );
      await c.$executeRaw`
        INSERT INTO chunks (document_id, source_id, ord, heading_path, content, token_count, content_hash, embedding)
        VALUES ${Prisma.join(values)}`;
    }
  });
}
