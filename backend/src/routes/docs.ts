// DOC mode API (docs/DOCS_MODE.md §4). Every route is scoped to the caller:
// another user's document reads as 404.
import { Router, type Request } from "express";
import { z } from "zod";
import { MODELS } from "../models.js";
import { AppError } from "../util/errors.js";
import { openSse } from "../util/sse.js";
import { userOf, type AuthUser } from "../auth/context.js";
import { refundDoc } from "../auth/limits.js";
import { loadRows } from "../files/context.js";
import { db } from "../db/prisma.js";
import { cancelJob, liveJob, registerJob, runningPipelineFor, type LiveJob } from "../docs/registry.js";
import { addSection, editSection, runRewrite, sectionsFor, startDoc, defaultDeps } from "../docs/pipeline.js";
import { normalizeOutline } from "../docs/outline.js";
import { anchorQuote, isUuid, prismaStore as store } from "../docs/store.js";
import { toDocx, toMarkdown, fileName } from "../docs/export.js";
import { DOC_LENGTHS, publicDoc, REFERENCES_ID, REWRITE_OPS, TAKEAWAYS_ID, type DocState } from "../docs/types.js";
import { finishJob, emit } from "../docs/registry.js";
import { runAs } from "../auth/context.js";
import { log } from "../util/logger.js";

export const docsRouter = Router();

const fileId = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i, "must be a file id");
const lenient = <T extends z.ZodTypeAny>(schema: T) => schema.optional().catch(undefined);
const profileSchema = z
  .object({
    name: lenient(z.string().max(60)),
    language: lenient(z.string().max(40)),
    tone: lenient(z.string().max(20)),
  })
  .catch({});

const createSchema = z.object({
  prompt: z.string().trim().min(3).max(8000),
  conversationId: z.string().max(64).optional(),
  length: z.enum(DOC_LENGTHS).default("standard"),
  webSearch: z.boolean().default(false),
  knowledge: z.boolean().default(false),
  sourceIds: z.array(z.string().max(64)).max(50).optional(),
  attachments: z.array(fileId).max(10).optional(),
  model: z.string().max(120).optional(),
  profile: profileSchema.optional(),
  reviewOutline: z.boolean().default(false),
});

function parse<T extends z.ZodTypeAny>(schema: T, body: unknown): z.infer<T> {
  const r = schema.safeParse(body ?? {});
  if (!r.success) throw new AppError(400, "bad_request", r.error.issues.map((i) => `${i.path.join(".") || "body"}: ${i.message}`).join("; "));
  return r.data;
}

function caller(req: Request): AuthUser & { id: string } {
  const u = userOf(req);
  if (!u.id) throw new AppError(403, "no_account", "Documents need a signed-in account");
  return u as AuthUser & { id: string };
}

const notFound = () => new AppError(404, "not_found", "Document not found");

/** The caller's document (live state while a job runs), or 404. */
async function load(req: Request): Promise<{ user: AuthUser & { id: string }; doc: DocState; job: LiveJob | undefined }> {
  const user = caller(req);
  const id = String(req.params.id);
  if (!isUuid(id)) throw notFound();
  const job = liveJob(id);
  if (job && job.userId === user.id) return { user, doc: job.state, job };
  const doc = await store.get(user.id, id);
  if (!doc) throw notFound();
  return { user, doc, job: undefined };
}

const busy = () => new AppError(409, "doc_busy", "This document is being written; wait for it to finish or stop it first.", true);

function oneRunningDoc(userId: string) {
  if (runningPipelineFor(userId)) throw new AppError(409, "doc_running", "You already have a document being written. Wait for it to finish or stop it.", true);
}

// ---- create / list / read ---------------------------------------------------------

docsRouter.post("/", async (req, res) => {
  const user = caller(req);
  try {
    const body = parse(createSchema, req.body);
    const requested = body.model && body.model !== "auto" ? body.model : undefined;
    if (requested && !MODELS.some((m) => m.id === requested)) throw new AppError(400, "bad_request", "Unknown model");
    oneRunningDoc(user.id);
    const attachments = [...new Set((body.attachments ?? []).map((a) => a.toLowerCase()))];
    if (attachments.length) await loadRows(attachments);
    let conversationId: string | null = null;
    if (body.conversationId && isUuid(body.conversationId)) {
      const conv = await db().conversation.findFirst({ where: { id: body.conversationId, userId: user.id }, select: { id: true } });
      conversationId = conv?.id ?? null;
    }
    const doc = await store.create({
      userId: user.id,
      conversationId,
      prompt: body.prompt,
      options: {
        length: body.length,
        web: body.webSearch,
        kb: body.knowledge,
        ...(body.sourceIds?.length ? { sourceIds: body.sourceIds } : {}),
        ...(requested ? { model: requested } : {}),
        ...(attachments.length ? { attachments } : {}),
        ...(body.profile && Object.keys(body.profile).length ? { profile: body.profile } : {}),
        ...(body.reviewOutline ? { reviewOutline: true } : {}),
        ...(body.conversationId ? { conversationId: body.conversationId } : {}),
      },
    });
    startDoc(doc, user, "full");
    res.status(202).json({ id: doc.id });
  } catch (e) {
    // The daily counter was taken by docLimit; give it back when nothing started.
    await refundDoc(user.id);
    throw e;
  }
});

docsRouter.get("/", async (req, res) => {
  const user = caller(req);
  const conversationId = typeof req.query.conversationId === "string" ? req.query.conversationId.slice(0, 64) : undefined;
  const docs = await store.list(user.id, conversationId);
  res.json({ docs: docs.map((d) => ({ ...d, running: !!liveJob(d.id) })) });
});

docsRouter.get("/:id", async (req, res) => {
  const { doc, job } = await load(req);
  res.json({ doc: publicDoc(doc, !!job) });
});

// SSE: a full snapshot first, then live events until the job ends. A finished
// document gets its snapshot and the stream closes. Reconnecting is safe.
docsRouter.get("/:id/events", async (req, res) => {
  const { doc, job } = await load(req);
  const sse = openSse(res);
  sse.send("doc_snapshot", { doc: publicDoc(doc, !!job) });
  if (!job) return sse.end();
  attach(job, sse, res);
});

function attach(job: LiveJob, sse: ReturnType<typeof openSse>, res: import("express").Response) {
  const onEvent = (event: string, data: unknown) => sse.send(event, data);
  const onEnd = () => sse.end();
  job.emitter.on("event", onEvent);
  job.emitter.once("end", onEnd);
  res.on("close", () => {
    job.emitter.off("event", onEvent);
    job.emitter.off("end", onEnd);
  });
}

docsRouter.patch("/:id", async (req, res) => {
  const { user, doc, job } = await load(req);
  const body = parse(z.object({ title: z.string().trim().min(1).max(160) }), req.body);
  doc.title = body.title;
  if (doc.outline) doc.outline.title = body.title;
  await store.update(user.id, doc.id, { title: body.title, ...(doc.outline ? { outline: doc.outline } : {}) });
  res.json({ doc: publicDoc(doc, !!job) });
});

docsRouter.delete("/:id", async (req, res) => {
  const { user, doc } = await load(req);
  cancelJob(doc.id);
  await store.remove(user.id, doc.id);
  res.status(204).end();
});

// ---- run control ----------------------------------------------------------------

const outlineSection = z.object({
  id: z.string().max(40).optional(),
  heading: z.string().max(200),
  goal: z.string().max(400).optional(),
  keyPoints: z.array(z.string().max(300)).max(10).optional(),
  queries: z.array(z.string().max(200)).max(4).optional(),
  visual: z.string().max(20).optional(),
  words: z.number().optional(),
  kind: z.string().max(20).optional(),
});
const startSchema = z.object({
  outline: z
    .object({
      title: z.string().max(200).optional(),
      subtitle: z.string().max(300).optional(),
      audience: z.string().max(200).optional(),
      style: z.string().max(20).optional(),
      sections: z.array(outlineSection).min(1).max(14),
      glossary: z.array(z.object({ term: z.string().max(100), definition: z.string().max(400) })).max(20).optional(),
    })
    .optional(),
});

docsRouter.post("/:id/start", async (req, res) => {
  const { user, doc, job } = await load(req);
  if (job) throw busy();
  if (doc.status !== "outline_ready") throw new AppError(409, "bad_state", "The outline is not waiting for review.");
  oneRunningDoc(user.id);
  const body = parse(startSchema, req.body);
  if (body.outline) {
    const merged = { ...doc.outline, ...body.outline, sections: body.outline.sections.filter((s) => !s.kind) };
    let normalized;
    try {
      normalized = normalizeOutline(merged, doc.options.length, doc.title, 14);
    } catch (e) {
      throw new AppError(400, "bad_request", (e as Error).message);
    }
    doc.outline = normalized.outline;
    if (body.outline.glossary) doc.glossary = normalized.glossary;
    doc.title = normalized.outline.title;
    doc.sections = sectionsFor(doc);
    await store.update(user.id, doc.id, { outline: doc.outline, glossary: doc.glossary, title: doc.title });
    await store.setSections(user.id, doc.id, doc.sections);
  }
  startDoc(doc, user, "write");
  res.status(202).json({ id: doc.id });
});

docsRouter.post("/:id/resume", async (req, res) => {
  const { user, doc, job } = await load(req);
  if (job) throw busy();
  if (!["partial", "failed", "interrupted"].includes(doc.status)) throw new AppError(409, "bad_state", "Only a stopped, failed or interrupted document can be resumed.");
  oneRunningDoc(user.id);
  startDoc(doc, user, doc.outline ? "resume" : "full");
  res.status(202).json({ id: doc.id });
});

docsRouter.post("/:id/cancel", async (req, res) => {
  const { doc } = await load(req);
  const cancelled = cancelJob(doc.id);
  res.status(202).json({ id: doc.id, cancelled });
});

// ---- sections -------------------------------------------------------------------

function sectionOf(doc: DocState, sid: string, writable = true) {
  const sec = doc.sections.find((s) => s.sectionId === sid);
  if (!sec || !doc.outline) throw new AppError(404, "not_found", "Section not found");
  if (writable && (sid === TAKEAWAYS_ID || sid === REFERENCES_ID)) throw new AppError(400, "bad_request", "This section is built automatically.");
  return sec;
}

const rewriteSchema = z
  .object({
    op: z.enum(REWRITE_OPS),
    instruction: z.string().trim().max(1000).optional(),
    selection: z.string().max(4000).optional(),
  })
  .refine((b) => b.op !== "custom" || !!b.instruction, { message: "instruction is required for op custom", path: ["instruction"] });

// Streams the section events (doc_section_start/delta/reset/done|failed, then
// doc_done) on this response; clients attached to /events see them too.
docsRouter.post("/:id/sections/:sid/rewrite", async (req, res) => {
  const { user, doc, job } = await load(req);
  if (job) throw busy();
  const sid = String(req.params.sid);
  sectionOf(doc, sid);
  const body = parse(rewriteSchema, req.body);
  const deps = defaultDeps();
  const live = registerJob(doc, "rewrite");
  const sse = openSse(res);
  sse.send("doc_snapshot", { doc: publicDoc(doc, true) });
  attach(live, sse, res);
  runAs(user, (() => {
    void runRewrite(live, sid, body.op, { instruction: body.instruction, selection: body.selection }, deps)
      .catch((e) => {
        log.error("doc rewrite crashed", { doc: doc.id, message: (e as Error).message?.slice(0, 200) });
        emit(live, "doc_error", { message: "Something went wrong while rewriting the section.", retryable: true });
      })
      .finally(() => finishJob(live));
  }) as import("express").NextFunction);
});

docsRouter.put("/:id/sections/:sid", async (req, res) => {
  const { doc, job } = await load(req);
  if (job) throw busy();
  const sid = String(req.params.sid);
  sectionOf(doc, sid);
  const body = parse(z.object({ markdown: z.string().max(60_000) }), req.body);
  const section = await editSection(store, doc, sid, body.markdown);
  res.json({ section, version: doc.version, words: doc.words });
});

docsRouter.post("/:id/sections", async (req, res) => {
  const { doc, job } = await load(req);
  if (job) throw busy();
  if (!doc.outline) throw new AppError(409, "bad_state", "The document has no outline yet.");
  const body = parse(z.object({ after: z.string().max(40).nullable().optional(), heading: z.string().trim().min(1).max(120), goal: z.string().trim().max(300).default("") }), req.body);
  if (body.after && !doc.outline.sections.some((s) => s.id === body.after)) throw new AppError(400, "bad_request", "after: unknown section");
  if (doc.outline.sections.filter((s) => !s.kind).length >= 14) throw new AppError(400, "bad_request", "A document has at most 14 sections.");
  const section = await addSection(store, doc, body.after ?? null, body.heading, body.goal || body.heading);
  res.status(201).json({ section, outline: doc.outline, version: doc.version });
});

docsRouter.get("/:id/versions/:sid", async (req, res) => {
  const { user, doc } = await load(req);
  const sid = String(req.params.sid);
  sectionOf(doc, sid, false);
  res.json({ versions: await store.revisions(user.id, doc.id, sid) });
});

// ---- highlights -----------------------------------------------------------------

function anchored(doc: DocState, h: Awaited<ReturnType<typeof store.highlights>>[number]) {
  const sec = doc.sections.find((s) => s.sectionId === h.sectionId);
  const at = sec ? anchorQuote(sec.markdown, h) : null;
  return { ...h, orphaned: !at, start: at?.start ?? -1, end: at?.end ?? -1 };
}

docsRouter.get("/:id/highlights", async (req, res) => {
  const { user, doc } = await load(req);
  const list = await store.highlights(user.id, doc.id);
  res.json({ highlights: list.map((h) => anchored(doc, h)) });
});

const highlightSchema = z.object({
  sectionId: z.string().max(40),
  quote: z.string().min(1).max(2000),
  prefix: z.string().max(64).default(""),
  suffix: z.string().max(64).default(""),
  color: z.string().max(20).default("yellow"),
  note: z.string().max(2000).nullable().optional(),
});

docsRouter.post("/:id/highlights", async (req, res) => {
  const { user, doc } = await load(req);
  const body = parse(highlightSchema, req.body);
  sectionOf(doc, body.sectionId, false);
  const h = await store.addHighlight(user.id, doc.id, { ...body, note: body.note ?? null });
  if (!h) throw notFound();
  res.status(201).json({ highlight: anchored(doc, h) });
});

async function deleteHighlight(req: Request, hid: string) {
  const { user, doc } = await load(req);
  if (!(await store.removeHighlight(user.id, doc.id, hid))) throw new AppError(404, "not_found", "Highlight not found");
}

docsRouter.delete("/:id/highlights/:hid", async (req, res) => {
  await deleteHighlight(req, String(req.params.hid));
  res.status(204).end();
});

docsRouter.delete("/:id/highlights", async (req, res) => {
  const hid = typeof req.query.id === "string" ? req.query.id : typeof req.body?.id === "string" ? req.body.id : "";
  if (!hid) throw new AppError(400, "bad_request", "id is required");
  await deleteHighlight(req, hid);
  res.status(204).end();
});

// ---- export ---------------------------------------------------------------------

docsRouter.get("/:id/export", async (req, res) => {
  const { doc } = await load(req);
  const format = req.query.format === "docx" ? "docx" : req.query.format === "md" || req.query.format === undefined ? "md" : null;
  if (!format) throw new AppError(400, "bad_request", "format must be md or docx");
  if (format === "md") {
    res.setHeader("Content-Type", "text/markdown; charset=utf-8");
    res.setHeader("Content-Disposition", `attachment; filename="${fileName(doc, "md")}"`);
    res.send(toMarkdown(doc));
    return;
  }
  const buf = await toDocx(doc);
  res.setHeader("Content-Type", "application/vnd.openxmlformats-officedocument.wordprocessingml.document");
  res.setHeader("Content-Disposition", `attachment; filename="${fileName(doc, "docx")}"`);
  res.send(buf);
});
