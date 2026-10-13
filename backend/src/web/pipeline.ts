// The web research pipeline: plan queries, ask a hedged chain of general web
// engines and (in parallel) the topical sources that fit the intent, return
// early once there is enough, merge (RRF + authority + recency + lexical
// relevance), rerank (embeddings when available, MMR for diversity), read the
// top pages and keep only the passages that answer the question.

import pLimit from "p-limit";
import { fetchText } from "../ingest/fetcher.js";
import { extractHtml, looksLikeHtml } from "../ingest/extract.js";
import { recordUsage } from "../db/usage.js";
import { embedQueries, embedTexts, embeddingsHealthy } from "../embeddings/index.js";
import { AppError } from "../util/errors.js";
import { USER_MSG } from "../util/userMessages.js";
import { log } from "../util/logger.js";
import { TtlLru } from "./lru.js";
import { selectPassages, terms } from "./passages.js";
import { planFromPreflight, planSearch, queryLang, type PlanContext, type SearchPlan } from "./plan.js";
import { snippetAnswers } from "./budget.js";
import { available, callProvider, CACHE_TTL_MS, PROVIDERS, type CallOutcome, type Provider } from "./providers.js";
import type { Candidate, Freshness, SearchCtx, WebResult } from "./types.js";
import { blendSemantic, mergeCandidates, mmr, type Merged, type MergeFocus } from "./rank.js";
import { hostOf, normalizeUrl } from "./url.js";
import { normalizeQuery, readPersistedValue, writePersisted } from "./cacheStore.js";
import { recordResearch } from "./stats.js";

export type ResearchOpts = {
  question: string;
  context?: PlanContext;
  /** A query already written for search (skips query rewriting). */
  focused?: string;
  signal?: AbortSignal;
  maxResults?: number;
  /** Pages to read in full when a hit only has a snippet. */
  fetchTop?: number;
  /** Cap on planned queries (1 for a single angle). */
  maxQueries?: number;
  /** Queries and freshness already written by the turn preflight: skips query planning. */
  preplanned?: { queries: string[]; fresh?: Freshness | null };
};

const PER_PROVIDER = 8;
/** A web engine still silent after this long gets a hedge: the next engine in the chain starts too. */
export const HEDGE_MS = 1_200;
/** An engine answer with fewer hits than this is thin: the next engine is asked as well. */
const MIN_WEB_HITS = 4;
/** Once the web engines answered, topical sources may add for this long before the pipeline moves on. */
export const TOPICAL_GRACE_MS = 900;
/** Hard cap on the search phase. */
const COLLECT_MAX_MS = 6_000;
const PAGE_TIMEOUT_MS = 5_000;
/** Total time the first token may wait for page reads. */
const FETCH_PHASE_MS = 2_200;
const PAGE_CONCURRENCY = 3;
const CONTENT_CHARS = 1500;
const FULL_CHARS = 12_000;
/** Embedding rerank budget; it runs alongside the page reads. */
const SEMANTIC_MS = 900;
const SEMANTIC_POOL = 12;
const PAGE_TTL_MS = 6 * 60 * 60_000;

const sleep = (ms: number, signal?: AbortSignal) =>
  new Promise<void>((resolve) => {
    const t = setTimeout(resolve, ms);
    signal?.addEventListener("abort", () => (clearTimeout(t), resolve()), { once: true });
  });

// ---- pages ---------------------------------------------------------------------

type Page = { title: string; text: string };
const pages = new TtlLru<Page | null>(200);
const pageLimit = pLimit(PAGE_CONCURRENCY);
const isPage = (v: unknown): v is Page => !!v && typeof (v as Page).text === "string" && typeof (v as Page).title === "string";

/** Readable text of a page (Readability + markdown), cached in memory and Postgres, time-boxed, SSRF-guarded by the shared fetcher. */
export async function fetchPage(url: string, signal?: AbortSignal, timeoutMs = PAGE_TIMEOUT_MS): Promise<Page | null> {
  const key = normalizeUrl(url) ?? url;
  const hit = pages.get(key);
  if (hit !== undefined) return hit;
  const shared = await readPersistedValue(`page|${key}`.slice(0, 400), isPage);
  if (shared) {
    pages.set(key, shared, PAGE_TTL_MS);
    return shared;
  }
  const started = Date.now();
  let timer: NodeJS.Timeout | undefined;
  try {
    const r = await Promise.race([
      fetchText(url, { delayMs: 0, maxBytes: 1_500_000 }),
      new Promise<never>((_, rej) => {
        timer = setTimeout(() => rej(new Error("page fetch timed out")), timeoutMs);
        signal?.addEventListener("abort", () => rej(new Error("aborted")), { once: true });
      }),
    ]);
    let title = "";
    let text = r.body;
    if (looksLikeHtml(r.contentType, r.body)) {
      const ex = extractHtml(r.body, r.url);
      title = ex.title ?? "";
      text = ex.markdown;
    }
    const out = text.trim().length >= 200 ? { title, text: text.trim().slice(0, 40_000) } : null;
    pages.set(key, out, out ? PAGE_TTL_MS : 5 * 60_000);
    if (out) writePersisted(`page|${key}`.slice(0, 400), out, PAGE_TTL_MS);
    recordUsage({ provider: "web", model: "page", kind: "fetch", ok: true, status: r.status, latencyMs: Date.now() - started });
    return out;
  } catch (e) {
    const msg = (e as Error).message ?? "";
    if (msg !== "aborted") {
      pages.set(key, null, 5 * 60_000);
      recordUsage({ provider: "web", model: "page", kind: "fetch", ok: false, latencyMs: Date.now() - started, errorMessage: msg });
    }
    return null;
  } finally {
    clearTimeout(timer);
  }
}

// ---- search phase ----------------------------------------------------------------

/**
 * Asks the web engines in chain order: the next one starts when the current
 * one fails, comes back thin, or is still silent after [hedgeMs]. Resolves on
 * the first good answer, or once every started call has settled.
 */
export function hedgedChain(chain: Provider[], query: string, ctx: SearchCtx, track: (p: Promise<CallOutcome>) => Promise<CallOutcome>, hedgeMs = HEDGE_MS): Promise<void> {
  return new Promise((resolve) => {
    let good = false;
    let i = 0;
    let pending = 0;
    let timer: NodeJS.Timeout | undefined;
    const next = () => {
      clearTimeout(timer);
      if (good) return;
      if (i >= chain.length || ctx.signal?.aborted) {
        if (pending === 0) resolve();
        return;
      }
      const p = chain[i++];
      pending++;
      void track(callProvider(p, query, ctx)).then((o) => {
        pending--;
        if (good) return;
        if (!o.error && !o.skipped && o.candidates.length >= MIN_WEB_HITS) {
          good = true;
          clearTimeout(timer);
          resolve();
          return;
        }
        next();
      });
      timer = setTimeout(next, hedgeMs);
    };
    next();
  });
}

export type CollectResult = { outcomes: CallOutcome[]; early: boolean };

/**
 * The search phase. Web engines (hedged) and intent-matched topical sources
 * run in parallel; it returns early once the web engines answered and either
 * the merged pool is big enough with some body text, or the topical sources
 * had [TOPICAL_GRACE_MS] more. Unavailable providers (disabled, quota-blocked,
 * circuit-open) are never called.
 */
export async function collect(plan: SearchPlan, signal: AbortSignal | undefined, opts: { want: number; lang?: string; focus: MergeFocus; providers?: Provider[]; graceMs?: number; hedgeMs?: number }): Promise<CollectResult> {
  const ctx: SearchCtx = { signal, fresh: plan.fresh, limit: PER_PROVIDER, lang: opts.lang };
  const pool = (opts.providers ?? PROVIDERS).filter(available);
  const web = pool.filter((p) => p.role === "web");
  const topical = pool.filter((p) => p.role === "secondary" && (p.intents === "any" || p.intents.some((i) => plan.intents.includes(i))));
  const outcomes: CallOutcome[] = [];
  let wake: (() => void) | null = null;
  const poke = () => {
    const w = wake;
    wake = null;
    w?.();
  };
  const track = (p: Promise<CallOutcome>) => p.then((o) => (outcomes.push(o), poke(), o));

  let webSettledAt = 0;
  const webTasks = [
    hedgedChain(web, plan.queries[0], ctx, track, opts.hedgeMs),
    // A second angle (comparisons) goes to the first available engine only.
    ...plan.queries.slice(1).map((q) => (web[0] ? track(callProvider(web[0], q, ctx)) : Promise.resolve())),
  ];
  let finished = false;
  const webAll = Promise.all(webTasks).then(() => {
    webSettledAt = Date.now();
    poke();
  });
  void Promise.all([webAll, ...topical.map((p) => track(callProvider(p, plan.queries[0], ctx)))]).then(() => {
    finished = true;
    poke();
  });

  const grace = opts.graceMs ?? TOPICAL_GRACE_MS;
  const deadline = Date.now() + COLLECT_MAX_MS;
  let early = false;
  while (!finished && !signal?.aborted && Date.now() < deadline) {
    if (webSettledAt) {
      const webHits = outcomes.some((o) => web.some((w) => w.name === o.provider) && o.candidates.length > 0);
      if (webHits) {
        const merged = mergeCandidates(outcomes.map((o) => o.candidates), plan.fresh, opts.focus);
        if ((merged.length >= opts.want && merged.some((c) => (c.text?.length ?? 0) >= 400)) || Date.now() - webSettledAt >= grace) {
          early = true;
          break;
        }
      }
    }
    const waitMs = webSettledAt ? Math.max(1, webSettledAt + grace - Date.now()) : deadline - Date.now();
    await new Promise<void>((resolve) => {
      const t = setTimeout(resolve, Math.min(waitMs, deadline - Date.now()));
      wake = () => (clearTimeout(t), resolve());
      signal?.addEventListener("abort", () => wake?.(), { once: true });
    });
  }
  const snapshot = [...outcomes];

  const got = new Set(snapshot.flatMap((o) => o.candidates.map((c) => normalizeUrl(c.url) ?? c.url)));
  if (got.size < 3 && !signal?.aborted) {
    const fallbacks = pool.filter((p) => p.role === "fallback");
    snapshot.push(...(await Promise.all(fallbacks.map((p) => callProvider(p, plan.queries[0], ctx)))));
  }
  return { outcomes: snapshot, early };
}

function summarize(outcomes: CallOutcome[]): string {
  return outcomes
    .map((o) => `${o.provider}:${o.skipped ? "skip" : o.error ? o.error : o.cached ? `cache${o.candidates.length}` : `${o.candidates.length}@${o.ms}ms`}`)
    .join(" ");
}

// ---- semantic rerank ----------------------------------------------------------------

/** Cosine similarity of each doc to the query, or null when embeddings are unavailable. */
export type WebEmbedder = (query: string, docs: string[]) => Promise<number[] | null>;

const defaultEmbedder: WebEmbedder = async (query, docs) => {
  if (embeddingsHealthy() !== "ok") return null;
  const [[q], ds] = await Promise.all([embedQueries([query]), embedTexts(docs, "document")]);
  return ds.map((d) => d.reduce((s, x, i) => s + x * (q[i] ?? 0), 0));
};
let embedder: WebEmbedder | null = defaultEmbedder;

/** Test seam / kill switch: null turns the embedding rerank off. Returns a restore function. */
export function setWebEmbedder(e: WebEmbedder | null): () => void {
  const prev = embedder;
  embedder = e;
  return () => void (embedder = prev);
}

async function semanticSims(query: string, items: Merged[], signal?: AbortSignal): Promise<Map<string, number>> {
  const out = new Map<string, number>();
  if (!embedder || items.length < 3) return out;
  const docs = items.map((c) => `${c.title}\n${c.snippet}\n${(c.text ?? "").slice(0, 600)}`.slice(0, 1200));
  const run = embedder(query, docs).catch(() => null);
  const sims = await Promise.race([run, sleep(SEMANTIC_MS, signal).then(() => null)]);
  if (sims) items.forEach((c, i) => Number.isFinite(sims[i]) && out.set(c.url, sims[i]));
  return out;
}

// ---- orchestration ----------------------------------------------------------------

const results = new TtlLru<WebResult[]>(300);

/** Identity of a whole research run: the normalized queries, freshness, language and output shape. */
export function researchCacheKey(plan: Pick<SearchPlan, "queries" | "fresh">, lang: string | undefined, maxResults: number, fetchTop: number): string {
  return `${plan.fresh}|${lang ?? "en"}|${maxResults}|${fetchTop}|${plan.queries.map(normalizeQuery).join("||")}`;
}

/** Test hook. */
export function clearResearchCache(): void {
  results.clear();
}

/** The full pipeline. Throws only when every provider failed or none could be asked. */
export async function researchWeb(opts: ResearchOpts): Promise<WebResult[]> {
  const started = Date.now();
  const maxResults = opts.maxResults ?? 5;
  const fetchTop = opts.fetchTop ?? 3;
  const plan = opts.preplanned?.queries.length ? planFromPreflight(opts.question, opts.preplanned.queries, opts.preplanned.fresh) : await planSearch(opts.question, opts.context ?? {}, opts.signal, opts.focused);
  if (opts.maxQueries) plan.queries = plan.queries.slice(0, opts.maxQueries);
  // Nothing searchable ("ok", "thanks", emoji): no provider call at all.
  if (!plan.queries.length || !terms(plan.queries.join(" ")).length) return [];
  const lang = queryLang(`${plan.queries.join(" ")}`);

  const key = researchCacheKey(plan, lang, maxResults, fetchTop);
  const hit = results.get(key);
  if (hit) {
    recordResearch({ ms: Date.now() - started, cached: true, results: hit.length });
    log.info("web research", { via: plan.via, fresh: plan.fresh, intents: plan.intents.join(","), queries: plan.queries.length, providers: "research-cache", merged: hit.length });
    return hit.map((r) => ({ ...r }));
  }

  const focus: MergeFocus = { queries: plan.queries, question: opts.question };
  const { outcomes, early } = await collect(plan, opts.signal, { want: maxResults + 1, lang, focus });
  const served = outcomes.filter((o) => !o.error && !o.skipped);
  const merged = mergeCandidates(outcomes.map((o) => o.candidates), plan.fresh, focus);
  log.info("web research", { via: plan.via, fresh: plan.fresh, intents: plan.intents.join(","), queries: plan.queries.length, providers: summarize(outcomes), merged: merged.length, early });
  if (!served.length) {
    if (opts.signal?.aborted) return [];
    log.warn("web research failed", { reason: "every web search provider failed or was unavailable", providers: summarize(outcomes) });
    throw new AppError(502, "upstream_failed", USER_MSG.webUnavailable, true);
  }

  const focusText = [...plan.queries, opts.question].join(" ");
  // Lexical shortlist first: the pages worth reading are picked from it while the embedding rerank runs.
  const shortlist = mmr(merged, maxResults + 2);
  const need = shortlist.filter((c) => (c.text?.length ?? 0) < 600 && !snippetAnswers(c, focusText)).slice(0, fetchTop);
  const fetched = new Map<string, { title: string; text: string }>();
  const [sims] = await Promise.all([
    merged.length > maxResults ? semanticSims(plan.queries[0], merged.slice(0, SEMANTIC_POOL), opts.signal) : Promise.resolve(new Map<string, number>()),
    // The page-reading phase is time-boxed: the first token never waits on a slow site (late pages still warm the page cache).
    Promise.race([
      Promise.all(
        need.map((c) =>
          pageLimit(async () => {
            if (opts.signal?.aborted) return;
            const page = await fetchPage(c.url, opts.signal);
            if (page) fetched.set(c.url, page);
          }),
        ),
      ),
      sleep(FETCH_PHASE_MS, opts.signal),
    ]),
  ]);

  // Final pick: semantic blend (when available), then MMR; a hit that was read in full ranks as it did, one with nothing to cite is skipped.
  const ranked = blendSemantic(merged.slice(0, SEMANTIC_POOL), sims);
  const pool = mmr(ranked, maxResults + 2);
  const out: WebResult[] = [];
  for (const c of pool) {
    const page = fetched.get(c.url);
    const body = page?.text ?? c.text;
    if (!body && c.snippet.length < 60) continue; // nothing to cite
    const text = (body ?? c.snippet).trim();
    const content = text.length <= CONTENT_CHARS ? text : selectPassages(text, focusText, { maxChars: CONTENT_CHARS, maxPassages: 4 });
    const title = c.title && c.title !== c.url ? c.title : page?.title || hostOf(c.url) || c.url;
    out.push({ title, url: c.url, content, full: text.slice(0, FULL_CHARS), source: c.source, published: c.published, site: hostOf(c.url) });
    if (out.length >= maxResults) break;
  }
  const ms = Date.now() - started;
  // Only a complete answer is reused; an empty one is retried next time.
  if (out.length) results.set(key, out, Math.min(CACHE_TTL_MS[plan.fresh], 60 * 60_000));
  recordResearch({ ms, results: out.length, early });
  log.info("web research done", { results: out.length, pagesRead: fetched.size, semantic: sims.size > 0, ms });
  return out;
}

export type { Candidate };
