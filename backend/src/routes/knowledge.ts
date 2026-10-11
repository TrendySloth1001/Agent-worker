import { Router } from "express";
import { createHash } from "node:crypto";
import { z } from "zod";
import { config } from "../config.js";
import { query } from "../db/pool.js";
import { connectors, detectType, SOURCE_TYPES, type SourceType } from "../ingest/connectors/index.js";
import { enqueue } from "../ingest/queue.js";
import { retrieve } from "../retrieval/search.js";
import { AppError } from "../util/errors.js";
import { userOf } from "../auth/context.js";

export const knowledgeRouter: Router = Router();

const uuid = z.string().uuid();

function toSource(r: any) {
  const active = r.status === "queued" || r.status === "running";
  return {
    id: r.id,
    type: r.type,
    uri: r.uri,
    title: r.title ?? null,
    status: r.status,
    progress: active ? { done: r.progress_done, total: r.progress_total ?? null } : null,
    docCount: r.doc_count,
    chunkCount: r.chunk_count,
    error: r.error ?? null,
    lastIngestedAt: r.last_ingested_at ? new Date(r.last_ingested_at).toISOString() : null,
    createdAt: new Date(r.created_at).toISOString(),
  };
}

const COLS = "id, type, uri, title, status, error, progress_done, progress_total, doc_count, chunk_count, created_at, last_ingested_at";

// Every query is limited to the caller's sources (`user_id IS NOT DISTINCT FROM`).
async function getSource(idRaw: string, uid: string | null) {
  const parsed = uuid.safeParse(idRaw);
  if (!parsed.success) throw new AppError(404, "not_found", "Source not found");
  const { rows } = await query(`SELECT ${COLS} FROM sources WHERE id=$1 AND user_id IS NOT DISTINCT FROM $2`, [parsed.data, uid]);
  if (!rows[0]) throw new AppError(404, "not_found", "Source not found");
  return rows[0];
}

knowledgeRouter.get("/sources", async (req, res) => {
  const { rows } = await query(`SELECT ${COLS} FROM sources WHERE user_id IS NOT DISTINCT FROM $1 ORDER BY created_at DESC LIMIT 200`, [userOf(req).id]);
  res.json({ sources: rows.map(toSource) });
});

const createBody = z.object({
  input: z.string().trim().min(1).max(2000),
  type: z.enum(["auto", ...SOURCE_TYPES]).default("auto"),
  limit: z.number().int().min(1).max(100).default(20),
});

knowledgeRouter.post("/sources", async (req, res) => {
  const body = createBody.parse(req.body ?? {});
  await query("SELECT 1"); // 503 early when the DB is down
  const type: Exclude<SourceType, "note"> = body.type === "auto" ? detectType(body.input) : body.type;
  const resolved = await connectors[type].resolve(body.input, body.limit);
  const uid = userOf(req).id;
  const dup = await query("SELECT id FROM sources WHERE type=$1 AND uri=$2 AND user_id IS NOT DISTINCT FROM $3", [type, resolved.uri, uid]);
  if (dup.rows[0]) throw new AppError(409, "conflict", `Source already exists (id ${dup.rows[0].id}). Use refresh to re-ingest.`);
  const ins = await query(
    `INSERT INTO sources (type, uri, title, options, user_id) VALUES ($1,$2,$3,$4,$5) RETURNING ${COLS}`,
    [type, resolved.uri, resolved.title ?? null, JSON.stringify({ ...(resolved.options ?? {}), limit: body.limit }), uid],
  );
  enqueue(ins.rows[0].id);
  res.status(202).json({ source: toSource(ins.rows[0]) });
});

const noteBody = z.object({
  title: z.string().trim().max(300).optional(),
  content: z.string().trim().min(1).max(50_000),
  conversationId: z.string().uuid().optional(),
  question: z.string().trim().max(4000).optional(),
});

function noteTitle(content: string): string {
  const line = content.split("\n").map((l) => l.replace(/^[#>\s*_`-]+/, "").trim()).find((l) => l.length > 0) ?? "Note";
  return line.length > 80 ? `${line.slice(0, 79).trimEnd()}…` : line;
}

knowledgeRouter.post("/notes", async (req, res) => {
  const b = noteBody.parse(req.body ?? {});
  await query("SELECT 1");
  const content = b.content.replace(/\u0000/g, "");
  const uri = `note:${createHash("sha256").update(content).digest("hex").slice(0, 24)}`;
  const uid = userOf(req).id;
  const dup = await query("SELECT id FROM sources WHERE type='note' AND uri=$1 AND user_id IS NOT DISTINCT FROM $2", [uri, uid]);
  if (dup.rows[0]) throw new AppError(409, "conflict", `Note already saved (id ${dup.rows[0].id}).`);
  const title = (b.title || noteTitle(content)).slice(0, 200);
  const ins = await query(
    `INSERT INTO sources (type, uri, title, options, user_id) VALUES ('note',$1,$2,$3,$4) RETURNING ${COLS}`,
    [uri, title, JSON.stringify({ content, title, question: b.question || undefined, conversationId: b.conversationId }), uid],
  );
  enqueue(ins.rows[0].id);
  res.status(202).json({ source: toSource(ins.rows[0]) });
});

knowledgeRouter.get("/stats", async (req, res) => {
  const r = await query(
    `SELECT (SELECT count(*)::int FROM sources WHERE user_id IS NOT DISTINCT FROM $1) AS s,
            (SELECT count(*)::int FROM documents d JOIN sources x ON x.id = d.source_id WHERE x.user_id IS NOT DISTINCT FROM $1) AS d,
            (SELECT count(*)::int FROM chunks c JOIN sources x ON x.id = c.source_id WHERE x.user_id IS NOT DISTINCT FROM $1) AS c`,
    [userOf(req).id],
  );
  res.json({ sources: r.rows[0].s, documents: r.rows[0].d, chunks: r.rows[0].c, embeddingModel: config.embeddingModel, dimensions: config.embeddingDimensions });
});

const searchBody = z.object({
  query: z.string().trim().min(1).max(2000),
  k: z.number().int().min(1).max(20).optional(),
  sourceIds: z.array(z.string().uuid()).max(50).optional(),
});

knowledgeRouter.post("/search", async (req, res) => {
  const b = searchBody.parse(req.body ?? {});
  const hits = await retrieve(b.query, { k: b.k, sourceIds: b.sourceIds });
  res.json({
    results: hits.map((h) => ({ chunkId: h.chunkId, score: h.score, title: h.title, url: h.url, headingPath: h.headingPath, content: h.content, sourceType: h.sourceType })),
  });
});

knowledgeRouter.get("/sources/:id", async (req, res) => {
  res.json({ source: toSource(await getSource(String(req.params.id), userOf(req).id)) });
});

knowledgeRouter.post("/sources/:id/refresh", async (req, res) => {
  const src = await getSource(String(req.params.id), userOf(req).id);
  if (src.type === "note") throw new AppError(400, "bad_request", "Notes cannot be refreshed");
  if (src.status !== "queued" && src.status !== "running") {
    const { rows } = await query(
      `UPDATE sources SET status='queued', error=NULL, progress_done=0, progress_total=NULL, updated_at=now() WHERE id=$1 RETURNING ${COLS}`,
      [src.id],
    );
    enqueue(src.id);
    res.status(202).json({ source: toSource(rows[0]) });
    return;
  }
  res.status(202).json({ source: toSource(src) });
});

knowledgeRouter.delete("/sources/:id", async (req, res) => {
  const src = await getSource(String(req.params.id), userOf(req).id);
  await query("DELETE FROM sources WHERE id=$1", [src.id]);
  res.status(204).end();
});
