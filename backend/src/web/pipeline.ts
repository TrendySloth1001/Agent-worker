// The web research pipeline: plan queries, fan out to the providers that fit
// the intent, merge (RRF + authority + recency + domain diversity), read the
// top pages, and keep only the passages that answer the question.

import pLimit from "p-limit";
import { fetchText } from "../ingest/fetcher.js";
import { extractHtml, looksLikeHtml } from "../ingest/extract.js";
import { recordUsage } from "../db/usage.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { TtlLru } from "./lru.js";
import { selectPassages } from "./passages.js";
import { planFromPreflight, planSearch, type PlanContext, type SearchPlan } from "./plan.js";
import { snippetAnswers } from "./budget.js";
import { callProvider, PROVIDERS, type CallOutcome } from "./providers.js";
import type { Candidate, Freshness, WebResult } from "./types.js";
import { diversify, mergeCandidates } from "./rank.js";
import { normalizeUrl } from "./url.js";

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

const PER_PROVIDER = 6;
const SECONDARY_GRACE_MS = 2_500;
const PAGE_TIMEOUT_MS = 6_000;
/** Total time the first token may wait for page reads. */
const FETCH_PHASE_MS = 2_500;
const PAGE_CONCURRENCY = 3;
const CONTENT_CHARS = 1500;
const FULL_CHARS = 12_000;
const STAGGER_MS = 350;

const sleep = (ms: number, signal?: AbortSignal) =>
  new Promise<void>((resolve) => {
    const t = setTimeout(resolve, ms);
    signal?.addEventListener("abort", () => (clearTimeout(t), resolve()), { once: true });
  });

// ---- pages ---------------------------------------------------------------------

const pages = new TtlLru<{ title: string; text: string } | null>(120);
const pageLimit = pLimit(PAGE_CONCURRENCY);

/** Readable text of a page (Readability + markdown), cached, time-boxed, SSRF-guarded by the shared fetcher. */
export async function fetchPage(url: string, signal?: AbortSignal, timeoutMs = PAGE_TIMEOUT_MS): Promise<{ title: string; text: string } | null> {
  const key = normalizeUrl(url) ?? url;
  const hit = pages.get(key);
  if (hit !== undefined) return hit;
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
    const out = text.trim().length >= 200 ? { title, text: text.trim() } : null;
    pages.set(key, out, out ? 30 * 60_000 : 5 * 60_000);
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

// ---- orchestration ----------------------------------------------------------------

/** Intents the free no-quota sources (Wikipedia, StackExchange, GitHub, arXiv, HN) answer well on their own. */
export function freeFirst(plan: SearchPlan): boolean {
  if (plan.fresh !== "evergreen") return false;
  if (plan.intents.some((i) => i === "code" || i === "academic" || i === "repo")) return true;
  // Encyclopedic is also the default intent: only a definitional question qualifies.
  return plan.intents.includes("encyclopedic") && /^(?:what (?:is|are|was|were)|who (?:is|was)|define|history of)\b/i.test(plan.queries[0] ?? "");
}

/** Whether free sources alone gave enough to answer: three distinct pages, one with real body text. */
export function enoughFree(outcomes: CallOutcome[]): boolean {
  const cands = outcomes.flatMap((o) => o.candidates);
  const urls = new Set(cands.map((c) => normalizeUrl(c.url) ?? c.url));
  return urls.size >= 3 && cands.some((c) => (c.text?.length ?? 0) >= 400);
}

async function collect(plan: SearchPlan, signal: AbortSignal | undefined): Promise<CallOutcome[]> {
  const ctx = { signal, fresh: plan.fresh, limit: PER_PROVIDER };
  const active = PROVIDERS.filter((p) => p.enabled());
  const primaries = active.filter((p) => p.role === "primary");
  const secondaries = active.filter((p) => p.role === "secondary" && (p.intents === "any" || p.intents.some((i) => plan.intents.includes(i))));
  const outcomes: CallOutcome[] = [];
  const track = (p: Promise<CallOutcome>) => p.then((o) => void outcomes.push(o));

  // Free, no-quota sources first when the intent fits them; the rate-limited Ollama search only if they came up short.
  if (freeFirst(plan) && secondaries.length > 0) {
    await Promise.all(secondaries.map((p) => track(callProvider(p, plan.queries[0], ctx))));
    if (enoughFree(outcomes) || signal?.aborted) return outcomes;
    const primaryTasks = primaries.flatMap((p) => plan.queries.map((q, i) => track(sleep(i * STAGGER_MS, signal).then(() => callProvider(p, q, ctx)))));
    await Promise.all(primaryTasks);
    return outcomes;
  }

  const primaryTasks = primaries.flatMap((p) =>
    plan.queries.map((q, i) => track(sleep(i * STAGGER_MS, signal).then(() => callProvider(p, q, ctx)))),
  );
  const secondaryTasks = secondaries.map((p) => track(callProvider(p, plan.queries[0], ctx)));

  if (primaryTasks.length) {
    await Promise.all(primaryTasks);
    await Promise.race([Promise.all(secondaryTasks), sleep(SECONDARY_GRACE_MS, signal)]);
  } else {
    await Promise.all(secondaryTasks);
  }

  const got = new Set(outcomes.flatMap((o) => o.candidates.map((c) => normalizeUrl(c.url) ?? c.url)));
  if (got.size < 3 && !signal?.aborted) {
    const fallbacks = active.filter((p) => p.role === "fallback");
    await Promise.all(fallbacks.map((p) => track(callProvider(p, plan.queries[0], ctx))));
  }
  return outcomes;
}

function summarize(outcomes: CallOutcome[]): string {
  return outcomes
    .map((o) => `${o.provider}:${o.skipped ? "skip" : o.error ? o.error : o.cached ? "cache" : `${o.candidates.length}@${o.ms}ms`}`)
    .join(" ");
}

/** The full pipeline. Throws only when every provider failed or was skipped. */
export async function researchWeb(opts: ResearchOpts): Promise<WebResult[]> {
  const started = Date.now();
  const maxResults = opts.maxResults ?? 5;
  const fetchTop = opts.fetchTop ?? 3;
  const plan = opts.preplanned?.queries.length ? planFromPreflight(opts.question, opts.preplanned.queries, opts.preplanned.fresh) : await planSearch(opts.question, opts.context ?? {}, opts.signal, opts.focused);
  if (opts.maxQueries) plan.queries = plan.queries.slice(0, opts.maxQueries);
  if (!plan.queries.length) return [];

  const outcomes = await collect(plan, opts.signal);
  const served = outcomes.filter((o) => !o.error && !o.skipped);
  const merged = mergeCandidates(outcomes.map((o) => o.candidates), plan.fresh, [...plan.queries, opts.question].join(" "));
  log.info("web research", { via: plan.via, fresh: plan.fresh, intents: plan.intents.join(","), queries: plan.queries.length, providers: summarize(outcomes), merged: merged.length });
  if (!served.length && outcomes.length) throw new AppError(502, "upstream_failed", "All web search providers failed", true);

  const pool = diversify(merged, maxResults + 2);
  const focusText = [...plan.queries, opts.question].join(" ");
  // Pages are only read when the hit has no body text of its own and its snippet does not already answer.
  const need = pool.filter((c) => (c.text?.length ?? 0) < 600 && !snippetAnswers(c, focusText)).slice(0, fetchTop);
  const fetched = new Map<Candidate, string>();
  // The whole page-reading phase is time-boxed: the first token never waits on a slow site (late pages still warm the page cache).
  await Promise.race([
    Promise.all(
      need.map((c) =>
        pageLimit(async () => {
          if (opts.signal?.aborted) return;
          const page = await fetchPage(c.url, opts.signal);
          if (page) fetched.set(c, page.text);
        }),
      ),
    ),
    sleep(FETCH_PHASE_MS, opts.signal),
  ]);

  const focus = [...plan.queries, opts.question].join(" ");
  const results: WebResult[] = [];
  for (const c of pool) {
    const body = fetched.get(c) ?? c.text;
    if (!body && c.snippet.length < 60) continue; // nothing to cite
    const text = (body ?? c.snippet).trim();
    const content = text.length <= CONTENT_CHARS ? text : selectPassages(text, focus, { maxChars: CONTENT_CHARS, maxPassages: 4 });
    results.push({ title: c.title, url: c.url, content, full: text.slice(0, FULL_CHARS), source: c.source, published: c.published });
    if (results.length >= maxResults) break;
  }
  log.info("web research done", { results: results.length, pagesRead: fetched.size, ms: Date.now() - started });
  return results;
}
