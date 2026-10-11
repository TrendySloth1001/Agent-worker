import { Router } from "express";
import { createHash } from "node:crypto";
import { z } from "zod";
import { config } from "../config.js";
import { db, type Prisma } from "../db/prisma.js";
import { connectors, detectType, SOURCE_TYPES, type SourceType } from "../ingest/connectors/index.js";
import { enqueue } from "../ingest/queue.js";
import { retrieve } from "../retrieval/search.js";
import { AppError } from "../util/errors.js";
import { userOf } from "../auth/context.js";

export const knowledgeRouter: Router = Router();

const uuid = z.string().uuid();

const SOURCE_SELECT = {
  id: true,
  type: true,
  uri: true,
  title: true,
  status: true,
  error: true,
  progressDone: true,
  progressTotal: true,
  docCount: true,
  chunkCount: true,
  createdAt: true,
  lastIngestedAt: true,
} satisfies Prisma.SourceSelect;

type SourceRow = Prisma.SourceGetPayload<{ select: typeof SOURCE_SELECT }>;

function toSource(r: SourceRow) {
  const active = r.status === "queued" || r.status === "running";
  return {
    id: r.id,
    type: r.type,
    uri: r.uri,
    title: r.title ?? null,
    status: r.status,
    progress: active ? { done: r.progressDone, total: r.progressTotal ?? null } : null,
    docCount: r.docCount,
    chunkCount: r.chunkCount,
    error: r.error ?? null,
    lastIngestedAt: r.lastIngestedAt ? r.lastIngestedAt.toISOString() : null,
    createdAt: r.createdAt.toISOString(),
  };
}

/** JSON for a jsonb column, without undefined members (as JSON.stringify wrote it before). */
const json = (v: Record<string, unknown>) => JSON.parse(JSON.stringify(v)) as Prisma.InputJsonObject;

// Every query is limited to the caller's sources (`user_id IS NOT DISTINCT FROM`).
async function getSource(idRaw: string, uid: string | null) {
  const parsed = uuid.safeParse(idRaw);
  if (!parsed.success) throw new AppError(404, "not_found", "Source not found");
  const row = await db().source.findFirst({ where: { id: parsed.data, userId: uid }, select: SOURCE_SELECT });
  if (!row) throw new AppError(404, "not_found", "Source not found");
  return row;
}

knowledgeRouter.get("/sources", async (req, res) => {
  const rows = await db().source.findMany({ where: { userId: userOf(req).id }, orderBy: { createdAt: "desc" }, take: 200, select: SOURCE_SELECT });
  res.json({ sources: rows.map(toSource) });
});

const createBody = z.object({
  input: z.string().trim().min(1).max(2000),
  type: z.enum(["auto", ...SOURCE_TYPES]).default("auto"),
  limit: z.number().int().min(1).max(100).default(20),
});

knowledgeRouter.post("/sources", async (req, res) => {
  const body = createBody.parse(req.body ?? {});
  await db().$queryRaw`SELECT 1`; // 503 early when the DB is down
  const type: Exclude<SourceType, "note"> = body.type === "auto" ? detectType(body.input) : body.type;
  const resolved = await connectors[type].resolve(body.input, body.limit);
  const uid = userOf(req).id;
  const dup = await db().source.findFirst({ where: { type, uri: resolved.uri, userId: uid }, select: { id: true } });
  if (dup) throw new AppError(409, "conflict", `Source already exists (id ${dup.id}). Use refresh to re-ingest.`);
  const ins = await db().source.create({
    data: { type, uri: resolved.uri, title: resolved.title ?? null, options: json({ ...(resolved.options ?? {}), limit: body.limit }), userId: uid },
    select: SOURCE_SELECT,
  });
  enqueue(ins.id);
  res.status(202).json({ source: toSource(ins) });
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
  await db().$queryRaw`SELECT 1`;
  const content = b.content.replace(/\u0000/g, "");
  const uri = `note:${createHash("sha256").update(content).digest("hex").slice(0, 24)}`;
  const uid = userOf(req).id;
  const dup = await db().source.findFirst({ where: { type: "note", uri, userId: uid }, select: { id: true } });
  if (dup) throw new AppError(409, "conflict", `Note already saved (id ${dup.id}).`);
  const title = (b.title || noteTitle(content)).slice(0, 200);
  const ins = await db().source.create({
    data: { type: "note", uri, title, options: json({ content, title, question: b.question || undefined, conversationId: b.conversationId }), userId: uid },
    select: SOURCE_SELECT,
  });
  enqueue(ins.id);
  res.status(202).json({ source: toSource(ins) });
});

knowledgeRouter.get("/stats", async (req, res) => {
  const mine = { userId: userOf(req).id };
  const [sources, documents, chunks] = await db().$transaction([
    db().source.count({ where: mine }),
    db().document.count({ where: { source: mine } }),
    db().chunk.count({ where: { source: mine } }),
  ]);
  res.json({ sources, documents, chunks, embeddingModel: config.embeddingModel, dimensions: config.embeddingDimensions });
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
    const row = await db().source.update({
      where: { id: src.id },
      data: { status: "queued", error: null, progressDone: 0, progressTotal: null, updatedAt: new Date() },
      select: SOURCE_SELECT,
    });
    enqueue(src.id);
    res.status(202).json({ source: toSource(row) });
    return;
  }
  res.status(202).json({ source: toSource(src) });
});

knowledgeRouter.delete("/sources/:id", async (req, res) => {
  const src = await getSource(String(req.params.id), userOf(req).id);
  await db().source.deleteMany({ where: { id: src.id } });
  res.status(204).end();
});
