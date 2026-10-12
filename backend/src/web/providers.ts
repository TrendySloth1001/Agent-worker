// Search providers behind one interface, a shared circuit breaker, a TTL
// cache keyed by freshness class, per-provider timeouts and telemetry.

import pLimit from "p-limit";
import { config } from "../config.js";
import { recordUsage } from "../db/usage.js";
import { log } from "../util/logger.js";
import { CircuitBreaker } from "./breaker.js";
import { TtlLru } from "./lru.js";
import { clip, isRateLimit, ollamaPost, statusOf } from "./ollama.js";
import { terms } from "./passages.js";
import type { Candidate, Freshness, Intent, SearchCtx } from "./types.js";

export type Provider = {
  name: string;
  /** primary: always asked; secondary: asked when its intent matches; fallback: only when the rest came up short. */
  role: "primary" | "secondary" | "fallback";
  intents: Intent[] | "any";
  timeoutMs: number;
  enabled(): boolean;
  /** Records its own telemetry (the Ollama client does). */
  selfRecorded?: boolean;
  search(query: string, ctx: SearchCtx): Promise<Candidate[]>;
};

export class ProviderError extends Error {
  constructor(
    message: string,
    public status = 0,
    public retryAfterMs = 0,
  ) {
    super(message);
  }
}

const UA = "AgentWorkerBot/1.0 (+https://sparky.cloudnsofts.com)";

async function http(url: string, ctx: SearchCtx, timeoutMs: number, init: RequestInit = {}): Promise<Response> {
  const timeout = AbortSignal.timeout(timeoutMs);
  const res = await fetch(url, {
    ...init,
    headers: { "User-Agent": UA, ...(init.headers as Record<string, string>) },
    signal: ctx.signal ? AbortSignal.any([ctx.signal, timeout]) : timeout,
  });
  if (!res.ok) {
    const ra = Number(res.headers.get("retry-after"));
    throw new ProviderError(`HTTP ${res.status}`, res.status, Number.isFinite(ra) && ra > 0 ? ra * 1000 : 0);
  }
  return res;
}

async function json(url: string, ctx: SearchCtx, timeoutMs: number, init?: RequestInit): Promise<any> {
  const res = await http(url, ctx, timeoutMs, { ...init, headers: { Accept: "application/json", ...(init?.headers as object) } });
  try {
    return await res.json();
  } catch {
    throw new ProviderError("response was not JSON", 502);
  }
}

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };
export function htmlToText(html: string): string {
  return html
    .replace(/<pre[^>]*>([\s\S]*?)<\/pre>/gi, (_m, c) => `\n\n${c.replace(/<[^>]+>/g, "")}\n\n`)
    .replace(/<\/(p|div|li|h\d|blockquote)>/gi, "\n\n")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&(#x?[0-9a-f]+|[a-z]+);/gi, (m, e: string) => {
      if (e[0] === "#") {
        const n = e[1].toLowerCase() === "x" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
        return Number.isFinite(n) && n > 0 && n < 0x110000 ? String.fromCodePoint(n) : m;
      }
      return ENTITIES[e.toLowerCase()] ?? m;
    })
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

const sleep = (ms: number, signal?: AbortSignal) =>
  new Promise<void>((resolve, reject) => {
    const t = setTimeout(resolve, ms);
    signal?.addEventListener("abort", () => (clearTimeout(t), reject(signal.reason)), { once: true });
  });

// ---- providers ---------------------------------------------------------------

const ollamaLimit = pLimit(2);

const ollama: Provider = {
  name: "ollama",
  role: "primary",
  intents: "any",
  timeoutMs: 10_000,
  selfRecorded: true,
  enabled: () => !!config.ollamaApiKey,
  async search(query, ctx) {
    // Ollama's search is the one that rate-limits: cap concurrency, retry a 429 once.
    const call = () => ollamaPost("web_search", { query, max_results: Math.min(ctx.limit, 8) }, ctx.signal, this.timeoutMs);
    const data = await ollamaLimit(async () => {
      try {
        return await call();
      } catch (e) {
        if (!isRateLimit(e)) throw e;
        await sleep(1200 + Math.random() * 800, ctx.signal);
        return await call();
      }
    }).catch((e) => {
      throw new ProviderError((e as Error).message, statusOf(e) || (isRateLimit(e) ? 429 : 502));
    });
    return (Array.isArray(data?.results) ? data.results : [])
      .filter((r: any) => typeof r?.url === "string")
      .map((r: any, rank: number): Candidate => ({
        title: clip(r.title, 200) || r.url,
        url: r.url,
        snippet: clip(r.content, 400),
        text: clip(r.content, 12_000),
        source: "ollama",
        rank,
      }));
  },
};

const wikipedia: Provider = {
  name: "wikipedia",
  role: "secondary",
  intents: ["encyclopedic", "academic"],
  timeoutMs: 5_000,
  enabled: () => true,
  async search(query, ctx) {
    const qs = new URLSearchParams({
      action: "query", format: "json", generator: "search", gsrsearch: query, gsrlimit: "3", gsrnamespace: "0",
      prop: "extracts", exintro: "1", explaintext: "1", exchars: "1800", redirects: "1",
    });
    const data = await json(`https://en.wikipedia.org/w/api.php?${qs}`, ctx, this.timeoutMs);
    const pages: any[] = Object.values(data?.query?.pages ?? {});
    return pages
      .sort((a, b) => (a.index ?? 0) - (b.index ?? 0))
      .filter((p) => typeof p.extract === "string" && p.extract.length > 60)
      .map((p, rank): Candidate => ({
        title: `${p.title} - Wikipedia`,
        url: `https://en.wikipedia.org/wiki/${encodeURIComponent(String(p.title).replace(/ /g, "_"))}`,
        snippet: clip(p.extract, 400),
        text: clip(p.extract, 4000),
        source: "wikipedia",
        rank,
      }));
  },
};

const hackerNews: Provider = {
  name: "hackernews",
  role: "secondary",
  intents: ["news", "code", "discussion", "repo"],
  timeoutMs: 5_000,
  enabled: () => true,
  async search(query, ctx) {
    const endpoint = ctx.fresh === "breaking" ? "search_by_date" : "search";
    const qs = new URLSearchParams({ query, tags: "story", hitsPerPage: "6" });
    const data = await json(`https://hn.algolia.com/api/v1/${endpoint}?${qs}`, ctx, this.timeoutMs);
    return (Array.isArray(data?.hits) ? data.hits : [])
      .filter((h: any) => h?.title && (h.points ?? 0) >= 5)
      .map((h: any, rank: number): Candidate => ({
        title: clip(h.title, 200),
        url: h.url || `https://news.ycombinator.com/item?id=${h.objectID}`,
        snippet: `${clip(h.title, 200)} (Hacker News, ${h.points} points, ${h.num_comments ?? 0} comments)${h.story_text ? ` ${htmlToText(clip(h.story_text, 600))}` : ""}`,
        source: "hackernews",
        rank,
        published: typeof h.created_at === "string" ? h.created_at.slice(0, 10) : undefined,
      }));
  },
};

const stackExchange: Provider = {
  name: "stackexchange",
  role: "secondary",
  intents: ["code"],
  timeoutMs: 6_000,
  enabled: () => true,
  async search(query, ctx) {
    const key: Record<string, string> = config.stackExchangeKey ? { key: config.stackExchangeKey } : {};
    const qs = new URLSearchParams({ order: "desc", sort: "relevance", q: query, site: "stackoverflow", accepted: "True", pagesize: "4", ...key });
    const data = await json(`https://api.stackexchange.com/2.3/search/advanced?${qs}`, ctx, this.timeoutMs);
    const qItems: any[] = (data?.items ?? []).filter((q: any) => q.accepted_answer_id);
    if (!qItems.length) return [];
    const ids = qItems.map((q) => q.accepted_answer_id).join(";");
    const aqs = new URLSearchParams({ site: "stackoverflow", filter: "withbody", ...key });
    const answers = await json(`https://api.stackexchange.com/2.3/answers/${ids}?${aqs}`, ctx, this.timeoutMs);
    const byId = new Map<number, any>((answers?.items ?? []).map((a: any) => [a.answer_id, a]));
    return qItems.flatMap((q, rank): Candidate[] => {
      const a = byId.get(q.accepted_answer_id);
      if (!a?.body) return [];
      const body = htmlToText(a.body);
      return [
        {
          title: htmlToText(q.title),
          url: q.link,
          snippet: clip(body, 400),
          text: `Question: ${htmlToText(q.title)}\n\nAccepted answer (${a.score ?? 0} votes):\n\n${clip(body, 4000)}`,
          source: "stackexchange",
          rank,
          published: q.last_activity_date ? new Date(q.last_activity_date * 1000).toISOString().slice(0, 10) : undefined,
        },
      ];
    });
  },
};

const githubRepos: Provider = {
  name: "github",
  role: "secondary",
  intents: ["repo"],
  timeoutMs: 6_000,
  enabled: () => !!config.githubToken,
  async search(query, ctx) {
    const qs = new URLSearchParams({ q: query, sort: "stars", order: "desc", per_page: "5" });
    const data = await json(`https://api.github.com/search/repositories?${qs}`, ctx, this.timeoutMs, {
      headers: { Authorization: `Bearer ${config.githubToken}`, Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28" },
    });
    return (Array.isArray(data?.items) ? data.items : []).map((r: any, rank: number): Candidate => ({
      title: `${r.full_name}${r.description ? `: ${clip(r.description, 120)}` : ""}`,
      url: r.html_url,
      snippet: `${r.description ?? ""} (${r.stargazers_count} stars, ${r.language ?? "n/a"}, last push ${String(r.pushed_at ?? "").slice(0, 10)}${r.topics?.length ? `, topics: ${r.topics.slice(0, 6).join(", ")}` : ""})`,
      source: "github",
      rank,
      published: typeof r.pushed_at === "string" ? r.pushed_at.slice(0, 10) : undefined,
    }));
  },
};

const arxiv: Provider = {
  name: "arxiv",
  role: "secondary",
  intents: ["academic"],
  timeoutMs: 7_000,
  enabled: () => true,
  async search(query, ctx) {
    const ts = terms(query).slice(0, 6);
    if (!ts.length) return [];
    const qs = new URLSearchParams({ search_query: ts.map((t) => `all:${t}`).join(" AND "), max_results: "4", sortBy: "relevance" });
    const res = await http(`https://export.arxiv.org/api/query?${qs}`, ctx, this.timeoutMs);
    const xml = await res.text();
    return [...xml.matchAll(/<entry>([\s\S]*?)<\/entry>/g)].flatMap((m, rank): Candidate[] => {
      const tag = (t: string) => htmlToText(m[1].match(new RegExp(`<${t}[^>]*>([\\s\\S]*?)</${t}>`))?.[1] ?? "").replace(/\s+/g, " ");
      const url = tag("id");
      const summary = tag("summary");
      if (!url || !summary) return [];
      return [{ title: tag("title"), url, snippet: clip(summary, 400), text: `${tag("title")}. ${summary}`, source: "arxiv", rank, published: tag("published").slice(0, 10) }];
    });
  },
};

const reddit: Provider = {
  name: "reddit",
  role: "secondary",
  intents: ["discussion"],
  timeoutMs: 5_000,
  enabled: () => config.webSearch.reddit,
  async search(query, ctx) {
    const qs = new URLSearchParams({ q: query, limit: "5", sort: "relevance", t: "year", raw_json: "1" });
    const data = await json(`https://www.reddit.com/search.json?${qs}`, ctx, this.timeoutMs);
    return (data?.data?.children ?? [])
      .map((c: any) => c.data)
      .filter((d: any) => d?.title && (d.score ?? 0) >= 5)
      .map((d: any, rank: number): Candidate => ({
        title: clip(d.title, 200),
        url: `https://www.reddit.com${d.permalink}`,
        snippet: `${clip(d.title, 200)} (r/${d.subreddit}, ${d.score} points) ${clip(d.selftext, 300)}`,
        text: d.selftext && d.selftext.length > 200 ? clip(d.selftext, 3000) : undefined,
        source: "reddit",
        rank,
        published: d.created_utc ? new Date(d.created_utc * 1000).toISOString().slice(0, 10) : undefined,
      }));
  },
};

/** Self-hosted SearXNG instances; public ones sit behind bot checks, so these are opt-in via SEARXNG_URLS. */
const searxng: Provider[] = config.webSearch.searxngUrls.map((base) => ({
  name: `searxng:${new URL(base).host}`,
  role: "fallback" as const,
  intents: "any" as const,
  timeoutMs: 6_000,
  enabled: () => true,
  async search(query: string, ctx: SearchCtx) {
    const qs = new URLSearchParams({ q: query, format: "json", language: "en", ...(ctx.fresh === "breaking" ? { time_range: "week" } : {}) });
    const data = await json(`${base}/search?${qs}`, ctx, 6_000);
    return (Array.isArray(data?.results) ? data.results : []).slice(0, ctx.limit).map((r: any, rank: number): Candidate => ({
      title: clip(r.title, 200) || r.url,
      url: r.url,
      snippet: clip(r.content, 400),
      source: "searxng",
      rank,
      published: typeof r.publishedDate === "string" ? r.publishedDate.slice(0, 10) : undefined,
    }));
  },
}));

export const PROVIDERS: Provider[] = [ollama, wikipedia, hackerNews, stackExchange, githubRepos, arxiv, reddit, ...searxng];

// ---- runner --------------------------------------------------------------------

export const breaker = new CircuitBreaker({ threshold: 3, cooldownMs: 60_000, maxCooldownMs: 10 * 60_000 });

const cache = new TtlLru<Candidate[]>(300);
export const CACHE_TTL_MS: Record<Freshness, number> = { breaking: 2 * 60_000, recent: 10 * 60_000, evergreen: 6 * 60 * 60_000 };
const EMPTY_TTL_MS = 60_000;

export type CallOutcome = { provider: string; candidates: Candidate[]; ms: number; cached?: boolean; skipped?: "circuit"; error?: string };

/** One provider call: cache, circuit breaker, timeout, telemetry. Never throws. */
export async function callProvider(p: Provider, query: string, ctx: SearchCtx): Promise<CallOutcome> {
  const key = `${p.name}|${ctx.fresh}|${query.toLowerCase().replace(/\s+/g, " ").trim()}`;
  const hit = cache.get(key);
  if (hit) return { provider: p.name, candidates: hit, ms: 0, cached: true };
  if (!breaker.allow(p.name)) return { provider: p.name, candidates: [], ms: 0, skipped: "circuit" };
  const started = Date.now();
  try {
    const candidates = (await p.search(query, ctx)).slice(0, ctx.limit);
    const ms = Date.now() - started;
    breaker.success(p.name);
    cache.set(key, candidates, candidates.length ? CACHE_TTL_MS[ctx.fresh] : EMPTY_TTL_MS);
    if (!p.selfRecorded) recordUsage({ provider: "web", model: p.name, kind: "search", ok: true, status: 200, latencyMs: ms, count: 1 });
    return { provider: p.name, candidates, ms };
  } catch (e) {
    const ms = Date.now() - started;
    if (ctx.signal?.aborted) return { provider: p.name, candidates: [], ms, error: "aborted" };
    const status = e instanceof ProviderError ? e.status : statusOf(e);
    const retryAfterMs = e instanceof ProviderError ? e.retryAfterMs : 0;
    const timedOut = (e as Error)?.name === "TimeoutError" || /timed? ?out/i.test((e as Error)?.message ?? "");
    // 4xx other than 429 on a search request is our problem or a block, not an outage: only 401/403 trips at once.
    const countable = status === 0 || status === 429 || status >= 500 || timedOut;
    if (status === 401 || status === 403) breaker.failure(p.name, { hard: true, retryAfterMs });
    else if (countable) breaker.failure(p.name, { retryAfterMs });
    if (!p.selfRecorded) {
      recordUsage({ provider: "web", model: p.name, kind: "search", ok: false, status: status || undefined, latencyMs: ms, errorMessage: timedOut ? "timeout" : (e as Error).message });
    }
    log.warn("web provider failed", { provider: p.name, status, message: (e as Error).message?.slice(0, 100), circuit: breaker.state(p.name) });
    return { provider: p.name, candidates: [], ms, error: timedOut ? "timeout" : status ? `http_${status}` : "error" };
  }
}
