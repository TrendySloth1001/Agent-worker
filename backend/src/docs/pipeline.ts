// DOC mode pipeline (docs/DOCS_MODE.md §2): context → outline → per-section
// research → sections (2 per doc, 3 across all docs) → takeaways + references.
// Runs as an in-process background job; state is persisted after every
// section and streamed to attached clients through the registry.
import pLimit from "p-limit";
import type { NextFunction } from "express";
import { ask } from "../llm/ask.js";
import { pickCandidates, preferForPrompt, runChat, ChatFailure } from "../llm/router.js";
import { webSearch, webFetch, type WebResult } from "../web/search.js";
import { imagesForQuery } from "../web/images.js";
import { scheduleIndex } from "../ingest/indexer.js";
import { retrieve, type KbHit } from "../retrieval/search.js";
import { loadRows, prepareMessages, waitForFiles } from "../files/context.js";
import { buildContextMessage, buildSystemPrompt, type ContextItem, type Profile } from "../prompts/system.js";
import { finishMessages, sectionMessages } from "../prompts/doc.js";
import { parseJson } from "../table/roundTable.js";
import { expectedMs, recordLatency } from "../table/latency.js";
import { withTelemetry } from "../db/usage.js";
import { db } from "../db/prisma.js";
import { runAs, type AuthUser } from "../auth/context.js";
import { log } from "../util/logger.js";
import { computeEvidence } from "../web/evidence.js";
import { emit, finishJob, registerJob, sectionSlots, Semaphore, type DocEventName, type LiveJob } from "./registry.js";
import { makeOutline, OUTLINE_MODELS, type AskFn } from "./outline.js";
import { pickSectionSources, researchSections, SourceBook, type SearchFn } from "./research.js";
import { keepValidTags, writeSection, type ImagesFn, type RunChatFn, type SectionEvents } from "./section.js";
import { prismaStore, type DocStore } from "./store.js";
import {
  citedIds,
  countWords,
  publicDoc,
  publicSource,
  REFERENCES_ID,
  TAKEAWAYS_ID,
  type DocSection,
  type DocSource,
  type DocState,
  type DocStatus,
  type OutlineSection,
  type RevisionReason,
  type RewriteOp,
} from "./types.js";

export const FINISH_MODELS = ["groq:openai/gpt-oss-20b", "ollama:gpt-oss:20b", "nvidia:openai/gpt-oss-20b"];

export type DocLimits = {
  maxCalls: number;
  maxSearches: number;
  wallMs: number;
  sectionMs: number;
  staggerMs: number;
  searchTimeoutMs: number;
  perDoc: number;
};

export const DEFAULT_LIMITS: DocLimits = { maxCalls: 13, maxSearches: 16, wallMs: 8 * 60_000, sectionMs: 150_000, staggerMs: 600, searchTimeoutMs: 12_000, perDoc: 2 };

export type DocDeps = {
  store: DocStore;
  ask: AskFn;
  runChat: RunChatFn;
  /** Section models, best first (≤3 attempts per section). */
  candidates: (requested: string | undefined, promptChars: number) => Promise<string[]>;
  outlineModels: () => Promise<string[]>;
  finishModels: () => Promise<string[]>;
  webSearch: SearchFn;
  webFetch: (url: string, signal?: AbortSignal) => Promise<WebResult | null>;
  images: ImagesFn;
  retrieve: (query: string, opts: { k?: number; sourceIds?: string[] }) => Promise<KbHit[]>;
  attachments: (ids: string[], prompt: string, signal: AbortSignal) => Promise<{ items: Array<{ id: string; title: string; url: string; text: string; full?: string }>; failed: string[] }>;
  /** Keeps the chat card (assistant message meta.doc) in sync. */
  linkMessage: (doc: DocState) => Promise<void>;
  limits: DocLimits;
  slots: Semaphore;
};

async function available(): Promise<Set<string>> {
  return new Set(await pickCandidates(undefined));
}

export function defaultDeps(): DocDeps {
  return {
    store: prismaStore,
    ask,
    runChat,
    candidates: async (requested, chars) => {
      const auto = preferForPrompt(await pickCandidates(undefined), chars);
      return (requested ? [requested, ...auto.filter((m) => m !== requested)] : auto).slice(0, 3);
    },
    outlineModels: async () => {
      const avail = await available();
      const first = OUTLINE_MODELS.filter((m) => avail.has(m));
      const fallback = [...avail].find((m) => !OUTLINE_MODELS.includes(m));
      return [...(first.length ? first : OUTLINE_MODELS), ...(fallback ? [fallback] : [])];
    },
    finishModels: async () => {
      const avail = await available();
      const list = FINISH_MODELS.filter((m) => avail.has(m));
      return (list.length ? list : FINISH_MODELS).slice(0, 2);
    },
    webSearch,
    webFetch,
    images: imagesForQuery,
    retrieve,
    attachments: async (ids, prompt, signal) => {
      let rows = await loadRows(ids);
      if ([...rows.values()].some((r) => r.status === "processing")) rows = await waitForFiles(ids, signal);
      const prepared = await prepareMessages([{ role: "user", content: prompt, attachments: ids }], rows, prompt);
      return { items: prepared.docs.map((d) => ({ id: d.id, title: d.title, url: d.url, text: d.text, full: d.full })), failed: prepared.failed };
    },
    linkMessage: async (doc) => {
      if (!doc.conversationId) return;
      const card = { id: doc.id, title: doc.title, status: doc.status, words: doc.words, sections: bodySections(doc).length };
      await db().$executeRaw`
        UPDATE conversation_messages SET meta = jsonb_set(meta, '{doc}', ${JSON.stringify(card)}::jsonb)
        WHERE conversation_id = ${doc.conversationId}::uuid AND meta->'doc'->>'id' = ${doc.id}`;
    },
    limits: DEFAULT_LIMITS,
    slots: sectionSlots,
  };
}

// ---- helpers ------------------------------------------------------------------

const URL_RE = /https?:\/\/[^\s<>"')\]]+/gi;
const isAbort = (e: unknown) => (e as Error)?.name === "AbortError" || (e as Error)?.name === "TimeoutError";

export function bodySections(doc: DocState): DocSection[] {
  const ids = new Set((doc.outline?.sections ?? []).filter((s) => !s.kind).map((s) => s.id));
  return doc.sections.filter((s) => ids.has(s.sectionId)).sort((a, b) => a.ord - b.ord);
}

export function outlineOf(doc: DocState, sectionId: string): OutlineSection | undefined {
  return doc.outline?.sections.find((s) => s.id === sectionId);
}

/** The system-prompt lines a document keeps from the chat prompt: today's date and the reply language. */
export function preambleFor(profile: unknown): string {
  return buildSystemPrompt("default", (profile ?? undefined) as Profile | undefined)
    .split("\n\n")
    .filter((p) => /^(Today's date|Language:)/.test(p))
    .join(" ");
}

function emptySection(s: OutlineSection, ord: number): DocSection {
  return { sectionId: s.id, ord, heading: s.heading, level: 2, markdown: "", summary: "", status: "pending", sourceIds: [], usedIds: [], evidence: [], images: [], model: null, words: 0, updatedAt: new Date().toISOString() };
}

/** Sections for a (new or edited) outline; keeps finished sections whose id survived. */
export function sectionsFor(doc: DocState): DocSection[] {
  return (doc.outline?.sections ?? []).map((s, i) => {
    const had = doc.sections.find((x) => x.sectionId === s.id);
    return had && had.heading === s.heading ? { ...had, ord: i } : emptySection(s, i);
  });
}

/** Cited sources in first-use order across the body sections. */
export function usedInOrder(doc: DocState): string[] {
  const out: string[] = [];
  for (const s of bodySections(doc)) for (const id of s.usedIds) if (!out.includes(id)) out.push(id);
  return out;
}

export function referencesMarkdown(doc: DocState): string {
  const byId = new Map(doc.sources.map((s) => [s.id, s]));
  return usedInOrder(doc)
    .map((id) => byId.get(id))
    .filter((s): s is DocSource => !!s)
    .map((s, i) => `${i + 1}. [${s.id}] [${s.title.replace(/[[\]]/g, "").replace(/\s+/g, " ").trim()}](${s.url.replace(/\(/g, "%28").replace(/\)/g, "%29").replace(/ /g, "%20")})${s.site ? ` · ${s.site}` : ""}`)
    .join("\n");
}

export function docWords(doc: DocState): number {
  return doc.sections.filter((s) => s.sectionId !== REFERENCES_ID && s.status === "done").reduce((n, s) => n + s.words, 0);
}

function sourceItems(sources: DocSource[]): { kb: ContextItem[]; web: ContextItem[]; files: ContextItem[] } {
  const item = (s: DocSource): ContextItem => ({ id: s.id, title: s.title, url: s.url, text: s.text });
  return {
    kb: sources.filter((s) => s.kind === "kb").map(item),
    web: sources.filter((s) => s.kind === "web").map(item),
    files: sources.filter((s) => s.kind === "file").map(item),
  };
}

/** Runs [fn] as [user] (ambient caller for KB retrieval and file access), detached from the request. */
function runAsUser(user: AuthUser, fn: () => Promise<void>): void {
  runAs(user, (() => void fn()) as NextFunction);
}

// ---- the job ------------------------------------------------------------------

type Ctx = {
  job: LiveJob;
  st: DocState;
  deps: DocDeps;
  book: SourceBook;
  signal: AbortSignal;
  budget: { calls: number };
  startedAt: number;
  phase: string;
  lastModel?: string;
  deadline: AbortSignal;
};

function send(c: Ctx, event: DocEventName, data: unknown) {
  emit(c.job, event, data);
}

async function persist(c: Ctx, patch: Parameters<DocStore["update"]>[2]) {
  Object.assign(c.st, patch);
  try {
    await c.deps.store.update(c.st.userId, c.st.id, patch);
  } catch (e) {
    log.warn("doc persist failed", { doc: c.st.id, message: (e as Error).message?.slice(0, 120) });
  }
}

async function persistSection(c: Ctx, s: DocSection) {
  s.updatedAt = new Date().toISOString();
  try {
    await c.deps.store.saveSection(c.st.userId, c.st.id, s);
  } catch (e) {
    log.warn("doc section persist failed", { doc: c.st.id, message: (e as Error).message?.slice(0, 120) });
  }
}

function statusEvent(c: Ctx) {
  const body = bodySections(c.st);
  const total = body.length;
  const done = body.filter((s) => s.status === "done").length;
  const left = body.filter((s) => s.status === "pending" || s.status === "writing").length;
  const per = expectedMs("doc_section", c.lastModel);
  let etaMs = Math.ceil(left / c.deps.limits.perDoc) * per;
  if (c.phase === "planning") etaMs += 20_000 + Math.ceil((total || 6) / c.deps.limits.perDoc) * per;
  if (c.phase === "researching") etaMs += 8_000;
  if (["planning", "researching", "writing"].includes(c.phase)) etaMs += 6_000;
  const elapsedMs = Date.now() - c.startedAt;
  etaMs = Math.max(0, Math.min(etaMs, c.deps.limits.wallMs - elapsedMs));
  send(c, "doc_status", { phase: c.phase, done, total, elapsedMs, etaMs });
}

async function setPhase(c: Ctx, phase: string, status?: DocStatus) {
  c.phase = phase;
  if (status) await persist(c, { status });
  statusEvent(c);
}

export type StartMode = "full" | "write" | "resume";

/** Starts (or resumes) the pipeline for [doc] as a live job. */
export function startDoc(doc: DocState, user: AuthUser, mode: StartMode, deps: DocDeps = defaultDeps()): LiveJob {
  const job = registerJob(doc, "pipeline");
  runAsUser(user, async () => {
    try {
      await runPipeline(job, mode, deps);
    } catch (e) {
      log.error("doc pipeline crashed", { doc: doc.id, message: (e as Error).message?.slice(0, 200) });
    } finally {
      finishJob(job);
    }
  });
  return job;
}

export async function runPipeline(job: LiveJob, mode: StartMode, deps: DocDeps): Promise<void> {
  const st = job.state;
  const deadline = AbortSignal.timeout(deps.limits.wallMs);
  const c: Ctx = {
    job,
    st,
    deps,
    book: new SourceBook(st.sources),
    signal: AbortSignal.any([job.ctl.signal, deadline]),
    budget: { calls: deps.limits.maxCalls },
    startedAt: Date.now(),
    phase: "planning",
    deadline,
  };
  c.book.shared = st.options.sharedIds ?? [];
  try {
    if (mode === "full" || !st.outline) {
      await setPhase(c, "planning", "planning");
      await gatherContext(c);
      if (c.signal.aborted) return await finish(c);
      const preamble = preambleFor(st.options.profile);
      let planned;
      try {
        planned = await withTelemetry({ purpose: "doc-outline", conversationId: st.conversationId ?? undefined }, async () =>
          makeOutline({
            prompt: st.prompt,
            length: st.options.length,
            ctx: {
              web: c.book.items.filter((s) => s.kind === "web").slice(0, 8).map((s) => ({ id: s.id, title: s.title, url: s.url, text: s.text })),
              kb: c.book.items.filter((s) => s.kind === "kb").slice(0, 8).map((s) => ({ id: s.id, title: s.title, text: s.text })),
              files: c.book.items.filter((s) => s.kind === "file").map((s) => ({ id: s.id, title: s.title, text: s.text })),
            },
            preamble,
            models: await deps.outlineModels(),
            ask: deps.ask,
            signal: c.signal,
          }),
        );
      } catch (e) {
        if (c.signal.aborted) return await finish(c);
        const message = (e as Error).message || "Could not plan the document.";
        c.budget.calls -= 2;
        await persist(c, { status: "failed" });
        send(c, "doc_error", { message, retryable: true });
        send(c, "doc_done", { status: "failed", words: 0, used: [], latencyMs: Date.now() - c.startedAt });
        await deps.linkMessage(st).catch(() => undefined);
        return;
      }
      c.budget.calls -= planned.calls;
      st.outline = planned.outline;
      st.glossary = planned.glossary;
      st.sections = sectionsFor(st);
      await persist(c, { title: planned.outline.title, outline: planned.outline, glossary: planned.glossary });
      try {
        await deps.store.setSections(st.userId, st.id, st.sections);
      } catch (e) {
        log.warn("doc sections persist failed", { doc: st.id, message: (e as Error).message?.slice(0, 120) });
      }
      send(c, "doc_outline", { title: planned.outline.title, subtitle: planned.outline.subtitle, sections: planned.outline.sections, glossary: planned.glossary });
      if (st.options.reviewOutline && mode === "full") {
        await setPhase(c, "outline_ready", "outline_ready");
        await deps.linkMessage(st).catch(() => undefined);
        return;
      }
    }
    await writeAll(c, mode);
    await finish(c);
  } catch (e) {
    log.error("doc pipeline failed", { doc: st.id, message: (e as Error).message?.slice(0, 200) });
    send(c, "doc_error", { message: "Something went wrong while writing the document.", retryable: true });
    await finish(c).catch(() => undefined);
  }
}

async function gatherContext(c: Ctx) {
  const { st, deps, book } = c;
  const o = st.options;
  const notice = (code: string, message: string) => send(c, "doc_notice", { code, message });
  const urls = [...new Set((st.prompt.match(URL_RE) ?? []).map((u) => u.replace(/[.,;:]+$/, "")))].slice(0, 3);
  const query = st.prompt.replace(URL_RE, " ").replace(/\s+/g, " ").trim().slice(0, 200) || st.prompt.slice(0, 200);
  const timed = () => AbortSignal.any([c.signal, AbortSignal.timeout(deps.limits.searchTimeoutMs)]);

  const [fetched, searched, kb, files] = await Promise.allSettled([
    Promise.all(urls.map((u) => deps.webFetch(u, timed()).catch(() => null))),
    o.web ? deps.webSearch(query, timed()) : Promise.resolve([] as WebResult[]),
    o.kb ? deps.retrieve(st.prompt.slice(0, 2000), { k: 8, sourceIds: o.sourceIds }) : Promise.resolve([] as KbHit[]),
    o.attachments?.length ? deps.attachments(o.attachments, st.prompt, c.signal) : Promise.resolve({ items: [], failed: [] as string[] }),
  ]);
  const shared: string[] = [];
  const added: DocSource[] = [];
  const addWeb = (r: WebResult) => {
    const { id, added: a } = book.add("web", r);
    if (a) added.push(a);
    if (!shared.includes(id)) shared.push(id);
  };
  if (fetched.status === "fulfilled") for (const r of fetched.value) if (r) addWeb(r);
  if (searched.status === "fulfilled") searched.value.forEach(addWeb);
  else if (o.web) notice("web_search_failed", "Web search failed; writing from the remaining sources.");
  if (kb.status === "fulfilled") {
    for (const h of kb.value) {
      const { added: a } = book.add("kb", { title: h.title || h.url, url: h.url, content: h.content, site: h.site, sourceType: h.sourceType, key: `${h.chunkId}` });
      if (a) added.push(a);
    }
  } else if (o.kb) notice("kb_unavailable", "Knowledge base is unavailable; writing without it.");
  if (files.status === "fulfilled") {
    for (const f of files.value.items) {
      const { added: a } = book.add("file", { title: f.title, url: f.url, content: f.text, full: f.full, site: "document", key: f.id });
      if (a) added.push(a);
    }
    if (files.value.failed.length) notice("attachment_failed", `Could not read: ${files.value.failed.join(", ")}`);
  } else if (o.attachments?.length) notice("attachment_failed", "Could not read the attachments.");
  book.shared = shared;
  await persist(c, { sources: book.items, options: { ...o, sharedIds: shared } });
  if (added.length) send(c, "doc_sources", { citations: added.map(publicSource) });
}

async function writeAll(c: Ctx, mode: StartMode) {
  const { st, deps, book } = c;
  const outline = st.outline!;
  const body = outline.sections.filter((s) => !s.kind);
  const secOf = (id: string) => st.sections.find((s) => s.sectionId === id)!;
  const todo = body.filter((s) => secOf(s.id) && secOf(s.id).status !== "done");

  // ---- research (only for sections that have no sources yet) ----
  const needs = todo.filter((s) => mode === "full" || mode === "write" || secOf(s.id).sourceIds.length === 0);
  let own = new Map<string, string[]>();
  if (st.options.web && needs.length && !c.signal.aborted) {
    await setPhase(c, "researching", "researching");
    const r = await researchSections({
      sections: needs,
      book,
      search: deps.webSearch,
      signal: c.signal,
      budget: deps.limits.maxSearches - (mode === "resume" ? 0 : 1),
      staggerMs: deps.limits.staggerMs,
      timeoutMs: deps.limits.searchTimeoutMs,
      onSources: (added) => send(c, "doc_sources", { citations: added.map(publicSource) }),
    });
    own = r.own;
    if (r.failed && r.failed === r.searches) send(c, "doc_notice", { code: "web_search_failed", message: "Section research failed; using the shared sources." });
  }
  for (const s of needs) secOf(s.id).sourceIds = pickSectionSources(s, own.get(s.id) ?? [], book);
  await persist(c, { sources: book.items });
  for (const s of needs) await persistSection(c, secOf(s.id));
  if (c.signal.aborted) return;

  // ---- sections ----
  await setPhase(c, "writing", "writing");
  const limit = pLimit(deps.limits.perDoc);
  await Promise.all(todo.map((s) => limit(() => writeOne(c, s))));
}

function sectionEvents(c: Ctx, sec: DocSection): SectionEvents {
  return {
    start: () => {},
    delta: (text) => {
      sec.markdown += text;
      send(c, "doc_section_delta", { sectionId: sec.sectionId, text });
    },
    reset: () => {
      sec.markdown = "";
      send(c, "doc_section_reset", { sectionId: sec.sectionId });
    },
    notice: (code, message) => send(c, "doc_notice", { code, message, sectionId: sec.sectionId }),
  };
}

async function writeOne(c: Ctx, os: OutlineSection) {
  const { st, deps, book } = c;
  const sec = st.sections.find((s) => s.sectionId === os.id)!;
  if (c.signal.aborted) return;
  const fail = async (message: string, retryable: boolean) => {
    sec.status = "failed";
    await persistSection(c, sec);
    send(c, "doc_section_failed", { sectionId: sec.sectionId, message, retryable });
    statusEvent(c);
  };
  // One call is kept back for the takeaways.
  if (c.budget.calls <= 1) return fail("The document reached its model-call budget; resume to finish this section.", true);

  const sources = sec.sourceIds.map((id) => book.get(id)).filter((s): s is DocSource => !!s);
  const items = sourceItems(sources);
  const summaries = bodySections(st)
    .filter((s) => s.status === "done" && s.summary)
    .map((s) => ({ heading: s.heading, summary: s.summary }));
  const messages = sectionMessages({
    preamble: preambleFor(st.options.profile),
    outline: st.outline!,
    glossary: st.glossary,
    section: os,
    summaries,
    context: buildContextMessage(items.kb, items.web, items.files),
    validTags: sources.map((s) => s.id),
  });
  const chars = messages.reduce((n, m) => n + m.content.length, 0);
  const candidates = await deps.candidates(st.options.model, chars);
  const secSignal = AbortSignal.any([c.signal, AbortSignal.timeout(deps.limits.sectionMs)]);
  let release: (() => void) | null = null;
  try {
    release = await deps.slots.acquire(secSignal);
    c.budget.calls--;
    sec.status = "writing";
    sec.markdown = "";
    send(c, "doc_section_start", { sectionId: sec.sectionId, model: candidates[0] ?? null, sourceIds: sec.sourceIds });
    statusEvent(c);
    const at = Date.now();
    const res = await withTelemetry({ purpose: "doc-section", conversationId: st.conversationId ?? undefined }, () =>
      writeSection({
        messages,
        candidates,
        sources,
        signal: secSignal,
        events: sectionEvents(c, sec),
        runChat: deps.runChat,
        images: deps.images,
        canContinue: () => (c.budget.calls > 1 ? (c.budget.calls--, true) : false),
      }),
    );
    recordLatency("doc_section", res.model, Date.now() - at);
    c.lastModel = res.model;
    Object.assign(sec, { markdown: res.markdown, summary: res.summary, model: res.model, usedIds: res.usedIds, evidence: res.evidence, images: res.images, words: res.words, status: "done" as const });
    await persistSection(c, sec);
    await addRevision(c.deps.store, st, sec.sectionId, sec.markdown, "generate");
    await persist(c, { words: docWords(st) });
    send(c, "doc_section_done", { sectionId: sec.sectionId, markdown: sec.markdown, words: sec.words, used: sec.usedIds, evidence: sec.evidence, images: sec.images, model: sec.model, summary: sec.summary });
    statusEvent(c);
  } catch (e) {
    if (c.job.cancelled) return fail("Stopped.", true);
    if (c.deadline.aborted) return fail("The document ran out of time; resume to finish this section.", true);
    if (isAbort(e) || secSignal.aborted) return fail("This section took too long.", true);
    if (e instanceof ChatFailure) return fail(e.message, e.retryable);
    log.warn("doc section failed", { doc: st.id, section: sec.sectionId, message: (e as Error).message?.slice(0, 120) });
    return fail("Something went wrong while writing this section.", true);
  } finally {
    release?.();
  }
}

async function addRevision(store: DocStore, st: DocState, sectionId: string, markdown: string, reason: RevisionReason) {
  try {
    await store.addRevision(st.userId, st.id, sectionId, st.version, markdown, reason);
  } catch (e) {
    log.warn("doc revision failed", { doc: st.id, message: (e as Error).message?.slice(0, 120) });
  }
}

/** Takeaways + abstract (one small model call), references (code), final status. */
async function finish(c: Ctx) {
  const { st, deps } = c;
  const body = bodySections(st);
  // Sections still marked writing (aborted mid-stream) become failed; pending ones stay pending.
  for (const s of body) if (s.status === "writing") {
    s.status = "failed";
    await persistSection(c, s);
    send(c, "doc_section_failed", { sectionId: s.sectionId, message: c.job.cancelled ? "Stopped." : "Interrupted.", retryable: true });
  }
  const done = body.filter((s) => s.status === "done");
  if (c.deadline.aborted && !c.job.cancelled) send(c, "doc_notice", { code: "time_budget", message: "The document hit its time limit; resume to finish the remaining sections." });

  if (done.length && st.outline) {
    await setPhase(c, "finishing");
    const summaries = done.map((s) => ({ heading: s.heading, summary: s.summary }));
    let takeaways: string[] = [];
    let abstract = "";
    if (!c.job.cancelled && c.budget.calls > 0) {
      for (const model of (await deps.finishModels()).slice(0, 2)) {
        try {
          c.budget.calls--;
          const raw = await withTelemetry({ purpose: "doc-finish" }, () =>
            deps.ask(model, finishMessages(st.outline!.title, summaries, preambleFor(st.options.profile)), { timeoutMs: 25_000, maxTokens: 1200, purpose: "doc-finish" }),
          );
          const j = parseJson(raw, "takeaways");
          takeaways = (Array.isArray(j.takeaways) ? j.takeaways : []).filter((t: unknown) => typeof t === "string" && t.trim()).map((t: string) => t.replace(/\s+/g, " ").trim()).slice(0, 5);
          abstract = typeof j.abstract === "string" ? j.abstract.replace(/\s+/g, " ").trim() : "";
          if (takeaways.length) break;
        } catch {
          /* next model, or the fallback below */
        }
        if (c.budget.calls <= 0) break;
      }
    }
    if (!takeaways.length) takeaways = summaries.map((s) => s.summary.split(/(?<=[.!?])\s/)[0]).filter(Boolean).slice(0, 5);
    if (!abstract) abstract = summaries.map((s) => s.summary).join(" ").slice(0, 900);
    const tk = st.sections.find((s) => s.sectionId === TAKEAWAYS_ID);
    if (tk) {
      const md = takeaways.map((t) => `- ${keepValidTags(t, new Set())}`).join("\n");
      send(c, "doc_section_start", { sectionId: TAKEAWAYS_ID, model: null, sourceIds: [] });
      Object.assign(tk, { markdown: md, summary: "", status: "done" as const, words: countWords(md), usedIds: [], evidence: [], images: [] });
      await persistSection(c, tk);
      send(c, "doc_section_done", { sectionId: TAKEAWAYS_ID, markdown: tk.markdown, words: tk.words, used: [], evidence: [], images: [], model: null });
    }
    await persist(c, { summary: abstract });
  }
  await refreshReferences(c.deps.store, st, (e, d) => send(c, e, d));

  const allDone = body.length > 0 && body.every((s) => s.status === "done");
  const status: DocStatus = allDone ? "done" : done.length || c.job.cancelled ? "partial" : "failed";
  await persist(c, { status, words: docWords(st), sources: c.book.items });
  c.phase = status;
  statusEvent(c);
  send(c, "doc_done", { status, words: st.words, used: usedInOrder(st), latencyMs: Date.now() - c.startedAt });
  await deps.linkMessage(st).catch((e) => log.warn("doc link failed", { message: (e as Error).message?.slice(0, 120) }));
  if (status === "done" || status === "partial") scheduleIndex("doc", st.userId, st.id, st.title, 500); // knowledge base
  log.info("doc", { doc: st.id, status, sections: `${done.length}/${body.length}`, words: st.words, sources: st.sources.length, latencyMs: Date.now() - c.startedAt });
}

/** Rebuilds the References section from the cited sources; emits its done event when it changed. */
async function refreshReferences(store: DocStore, st: DocState, send: (e: DocEventName, d: unknown) => void) {
  const ref = st.sections.find((s) => s.sectionId === REFERENCES_ID);
  if (!ref) return;
  const md = referencesMarkdown(st);
  const used = usedInOrder(st);
  if (ref.markdown === md && ref.status === "done") return;
  Object.assign(ref, { markdown: md, status: "done" as const, usedIds: used, words: 0, updatedAt: new Date().toISOString() });
  try {
    await store.saveSection(st.userId, st.id, ref);
  } catch {
    /* best effort */
  }
  send("doc_section_done", { sectionId: REFERENCES_ID, markdown: md, words: 0, used, evidence: [], images: [], model: null });
}

// ---- section rewrite / edit / add ---------------------------------------------

/** Rewrites one section inside a registered "rewrite" job: streams the section events, saves a revision, bumps the version. On failure the previous text stays. */
export async function runRewrite(job: LiveJob, sectionId: string, op: RewriteOp, opts: { instruction?: string; selection?: string }, deps: DocDeps): Promise<void> {
  const st = job.state;
  const started = Date.now();
  const c: Ctx = { job, st, deps, book: new SourceBook(st.sources), signal: job.ctl.signal, budget: { calls: 2 }, startedAt: started, phase: "writing", deadline: AbortSignal.timeout(deps.limits.sectionMs * 2) };
  c.book.shared = st.options.sharedIds ?? [];
  const sec = st.sections.find((s) => s.sectionId === sectionId)!;
  const os = outlineOf(st, sectionId)!;
  const before = { ...sec };

  // A new (added) section without sources gets one search of its own.
  if (!sec.sourceIds.length) {
    let own: string[] = [];
    if (st.options.web) {
      try {
        const results = await deps.webSearch(`${os.heading} ${st.outline?.title ?? ""}`.slice(0, 200), AbortSignal.any([c.signal, AbortSignal.timeout(deps.limits.searchTimeoutMs)]));
        const added: DocSource[] = [];
        for (const r of results) {
          const { id, added: a } = c.book.add("web", r);
          if (a) added.push(a);
          own.push(id);
        }
        if (added.length) send(c, "doc_sources", { citations: added.map(publicSource) });
      } catch {
        own = [];
      }
    }
    sec.sourceIds = pickSectionSources(os, own, c.book);
    st.sources = c.book.items;
  }
  const sources = sec.sourceIds.map((id) => c.book.get(id)).filter((s): s is DocSource => !!s);
  const items = sourceItems(sources);
  const summaries = bodySections(st)
    .filter((s) => s.status === "done" && s.summary && s.sectionId !== sectionId)
    .map((s) => ({ heading: s.heading, summary: s.summary }));
  const messages = sectionMessages({
    preamble: preambleFor(st.options.profile),
    outline: st.outline!,
    glossary: st.glossary,
    section: os,
    summaries,
    context: buildContextMessage(items.kb, items.web, items.files),
    validTags: sources.map((s) => s.id),
    rewrite: { op, current: before.markdown, instruction: opts.instruction, selection: opts.selection },
  });
  const words = op === "expand" ? Math.round(Math.max(before.words, os.words) * 1.6) : op === "shorten" ? Math.round(Math.max(before.words, 150) * 0.6) : os.words;
  const candidates = await deps.candidates(st.options.model, messages.reduce((n, m) => n + m.content.length, 0) + words);
  const secSignal = AbortSignal.any([c.signal, AbortSignal.timeout(deps.limits.sectionMs)]);
  let release: (() => void) | null = null;
  try {
    release = await deps.slots.acquire(secSignal);
    sec.status = "writing";
    sec.markdown = "";
    send(c, "doc_section_start", { sectionId, model: candidates[0] ?? null, sourceIds: sec.sourceIds });
    const res = await withTelemetry({ purpose: "doc-rewrite" }, () =>
      writeSection({ messages, candidates, sources, signal: secSignal, events: sectionEvents(c, sec), runChat: deps.runChat, images: deps.images, canContinue: () => (c.budget.calls > 0 ? (c.budget.calls--, true) : false) }),
    );
    recordLatency("doc_section", res.model, Date.now() - started);
    Object.assign(sec, { markdown: res.markdown, summary: res.summary, model: res.model, usedIds: res.usedIds, evidence: res.evidence, images: res.images, words: res.words, status: "done" as const });
    st.version += 1;
    await persistSection(c, sec);
    await addRevision(deps.store, st, sectionId, sec.markdown, op);
    send(c, "doc_section_done", { sectionId, markdown: sec.markdown, words: sec.words, used: sec.usedIds, evidence: sec.evidence, images: sec.images, model: sec.model, summary: sec.summary });
  } catch (e) {
    Object.assign(sec, before);
    const message = job.cancelled ? "Stopped." : e instanceof ChatFailure ? e.message : isAbort(e) ? "This section took too long." : "Something went wrong while rewriting this section.";
    send(c, "doc_section_failed", { sectionId, message, retryable: true });
  } finally {
    release?.();
  }
  await refreshReferences(deps.store, st, (e, d) => send(c, e, d));
  const body = bodySections(st);
  if (st.status === "partial" && body.every((s) => s.status === "done")) st.status = "done";
  await persist(c, { version: st.version, words: docWords(st), sources: c.book.items, status: st.status });
  send(c, "doc_done", { status: st.status, words: st.words, used: usedInOrder(st), latencyMs: Date.now() - started });
  await deps.linkMessage(st).catch(() => undefined);
  if (st.status === "done" || st.status === "partial") scheduleIndex("doc", st.userId, st.id, st.title); // re-index the revised section
}

/** Manual edit: keeps the user's Markdown, drops unknown citation tags, recomputes evidence. */
export async function editSection(store: DocStore, st: DocState, sectionId: string, markdown: string): Promise<DocSection> {
  const sec = st.sections.find((s) => s.sectionId === sectionId)!;
  const valid = new Set(st.sources.map((s) => s.id));
  const md = keepValidTags(markdown.replace(/\r/g, ""), valid).trim();
  const used = citedIds(md).filter((id) => valid.has(id));
  const byId = new Map(st.sources.map((s) => [s.id, s]));
  let evidence: DocSection["evidence"] = [];
  try {
    evidence = computeEvidence(md, used.map((id) => ({ id, text: byId.get(id)?.full ?? byId.get(id)?.text ?? "" })));
  } catch {
    evidence = [];
  }
  Object.assign(sec, { markdown: md, usedIds: used, evidence, words: countWords(md), status: "done" as const, updatedAt: new Date().toISOString() });
  for (const id of used) if (!sec.sourceIds.includes(id)) sec.sourceIds.push(id);
  st.version += 1;
  await store.saveSection(st.userId, st.id, sec);
  await store.addRevision(st.userId, st.id, sectionId, st.version, md, "edit");
  if (sectionId !== REFERENCES_ID) await refreshReferences(store, st, () => {});
  st.words = docWords(st);
  await store.update(st.userId, st.id, { version: st.version, words: st.words });
  if (st.status === "done" || st.status === "partial") scheduleIndex("doc", st.userId, st.id, st.title);
  return sec;
}

/** Adds a pending section after `after` (null: first). Write it with a `regenerate` rewrite. */
export async function addSection(store: DocStore, st: DocState, after: string | null, heading: string, goal: string): Promise<DocSection> {
  const outline = st.outline!;
  const n = Math.max(0, ...outline.sections.filter((s) => !s.kind).map((s) => Number(s.id.slice(1)) || 0)) + 1;
  const os: OutlineSection = { id: `s${n}`, heading: heading.trim().slice(0, 120), goal: goal.trim().slice(0, 300), keyPoints: [], queries: [], visual: "none", words: 400 };
  let at = after ? outline.sections.findIndex((s) => s.id === after) + 1 : 0;
  const firstClosing = outline.sections.findIndex((s) => s.kind);
  if (at <= 0 && after) at = firstClosing >= 0 ? firstClosing : outline.sections.length;
  if (firstClosing >= 0 && at > firstClosing) at = firstClosing;
  outline.sections.splice(at, 0, os);
  st.sections = sectionsFor(st);
  st.version += 1;
  await store.update(st.userId, st.id, { outline, version: st.version });
  await store.setSections(st.userId, st.id, st.sections);
  return st.sections.find((s) => s.sectionId === os.id)!;
}

export { publicDoc };
