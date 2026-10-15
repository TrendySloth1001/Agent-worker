// Search providers behind one interface, a shared circuit breaker, a TTL
// cache keyed by freshness class, per-provider timeouts and telemetry.
//
// Roles:
//  - web: general web engines, asked as a hedged chain in PROVIDERS order
//    (first one, then the next only if it is slow, fails or comes back thin);
//  - secondary: topical sources (Wikipedia, StackOverflow, arXiv, HN, news...)
//    asked in parallel when the question's intent fits them;
//  - fallback: only when everything else came up short.

import { config } from "../config.js";
import { recordUsage } from "../db/usage.js";
import { log } from "../util/logger.js";
import { redactForExternal } from "../nlp/pii.js";
import { CircuitBreaker } from "./breaker.js";
import { TtlLru } from "./lru.js";
import { readPersisted, searchCacheKey, writePersisted } from "./cacheStore.js";
import { clip, OLLAMA_WEB_ID, OllamaWebError, ollamaPost, statusOf, isRateLimit } from "./ollama.js";
import { isQuotaBlocked } from "../llm/quota.js";
import { terms } from "./passages.js";
import { htmlToText } from "./html.js";
import { BROWSER_UA, TEXT_BROWSER_UA, bingParams, duckDuckGoForm, parseBingRss, parseBrave, parseBraveHtml, parseDuckDuckGo, parseDuckDuckGoLite, engineQuery } from "./general.js";
import { recordOutcome } from "./stats.js";
import type { Candidate, Freshness, Intent, SearchCtx } from "./types.js";

export { htmlToText } from "./html.js";

export type Provider = {
  name: string;
  role: "web" | "secondary" | "fallback";
  intents: Intent[] | "any";
  timeoutMs: number;
  enabled(): boolean;
  /** Records its own telemetry (the Ollama client does). */
  selfRecorded?: boolean;
  /** Scraped engines: a 429 without Retry-After means "blocked for a while", not "try again in a second". */
  blockCooldownMs?: number;
  /** Circuit shared with other endpoints of the same service (they share its per-IP limits). */
  breakerKey?: string;
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
/** How long a scraped engine that started refusing us (429, bot check) is left alone. */
const BLOCKED_COOLDOWN_MS = 10 * 60_000;
/** Minimum time an engine that answered 429 is skipped. */
const RATE_LIMIT_COOLDOWN_MS = 2 * 60_000;

const off = (name: string) => config.webSearch.disabled.has(name);

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

// ---- general web engines -------------------------------------------------------

const brave: Provider = {
  name: "brave",
  role: "web",
  intents: "any",
  timeoutMs: 4_000,
  enabled: () => !!config.webSearch.braveKey && !off("brave"),
  async search(query, ctx) {
    const qs = new URLSearchParams({ q: query, count: String(Math.min(ctx.limit + 2, 10)), extra_snippets: "1", ...(ctx.region ? { country: ctx.region.toUpperCase() } : {}), ...(ctx.fresh === "breaking" ? { freshness: "pw" } : {}) });
    const data = await json(`https://api.search.brave.com/res/v1/web/search?${qs}`, ctx, this.timeoutMs, {
      headers: { "X-Subscription-Token": config.webSearch.braveKey!, "Accept-Encoding": "gzip" },
    });
    return parseBrave(data);
  },
};

/**
 * Keyless engines rate-limit bursts per IP: calls to one engine are spaced
 * [gapMs] apart process-wide (a waiting call is overtaken by the hedge).
 */
const nextSlot = new Map<string, number>();
export async function engineSlot(name: string, gapMs: number, signal?: AbortSignal): Promise<void> {
  const now = Date.now();
  const at = Math.max(now, nextSlot.get(name) ?? 0);
  // A long queue is not worth waiting in: the hedge or the next engine answers sooner (not a failure, the circuit stays closed).
  if (at - now > 3 * gapMs) throw new ProviderError(`${name} queue full`, 499);
  nextSlot.set(name, at + gapMs);
  if (at > now) await sleep(at - now, signal);
}

const sleep = (ms: number, signal?: AbortSignal) =>
  new Promise<void>((resolve, reject) => {
    const t = setTimeout(resolve, ms);
    signal?.addEventListener("abort", () => (clearTimeout(t), reject(signal.reason)), { once: true });
  });

/** DuckDuckGo answers 403 when it rate-limits an IP and 202 + a challenge page when it suspects a bot. */
async function duckDuckGoPost(url: string, query: string, ctx: SearchCtx, timeoutMs: number): Promise<string> {
  await engineSlot("duckduckgo", 2_000, ctx.signal);
  let res: Response;
  try {
    res = await http(url, ctx, timeoutMs, {
      method: "POST",
      body: duckDuckGoForm(query, ctx.fresh, ctx.lang, ctx.region),
      headers: { "User-Agent": TEXT_BROWSER_UA, Accept: "text/html", "Content-Type": "application/x-www-form-urlencoded", Referer: new URL(url).origin + "/" },
    });
  } catch (e) {
    // A 403 is DuckDuckGo's per-IP rate limit: a soft block, retried after a cooldown (not an auth failure).
    if (e instanceof ProviderError && e.status === 403) throw new ProviderError("duckduckgo rate limit", 429, 5 * 60_000);
    throw e;
  }
  const html = await res.text();
  if (res.status === 202 || /anomaly-modal|challenge-form/i.test(html)) throw new ProviderError("duckduckgo bot check", 429, BLOCKED_COOLDOWN_MS);
  return html;
}

const duckduckgo: Provider = {
  name: "duckduckgo",
  blockCooldownMs: 5 * 60_000,
  breakerKey: "duckduckgo",
  role: "web",
  intents: "any",
  timeoutMs: 4_000,
  enabled: () => !off("duckduckgo"),
  async search(query, ctx) {
    return parseDuckDuckGo(await duckDuckGoPost("https://html.duckduckgo.com/html/", query, ctx, this.timeoutMs));
  },
};

/** Brave Search's public HTML results page (no key; an independent index). */
const braveHtml: Provider = {
  name: "brave-html",
  blockCooldownMs: 5 * 60_000,
  role: "web",
  intents: "any",
  timeoutMs: 4_500,
  enabled: () => !off("brave-html") && !config.webSearch.braveKey,
  async search(query, ctx) {
    await engineSlot("brave-html", 1_000, ctx.signal);
    const qs = new URLSearchParams({ q: engineQuery(query), source: "web", ...(ctx.fresh === "breaking" ? { tf: "pw" } : {}) });
    const res = await http(`https://search.brave.com/search?${qs}`, ctx, this.timeoutMs, { headers: { "User-Agent": BROWSER_UA, Accept: "text/html", "Accept-Language": ctx.lang === "hi" ? "hi,en;q=0.8" : "en-US,en;q=0.9" } });
    const html = await res.text();
    if (/captcha/i.test(res.url) || (!/data-type="web"/.test(html) && /captcha|are you a robot/i.test(html))) throw new ProviderError("brave bot check", 429, BLOCKED_COOLDOWN_MS);
    return parseBraveHtml(html);
  },
};

/** Same index, separate endpoint: the last keyless hedge. */
const duckduckgoLite: Provider = {
  name: "duckduckgo-lite",
  blockCooldownMs: 5 * 60_000,
  breakerKey: "duckduckgo",
  role: "web",
  intents: "any",
  timeoutMs: 4_000,
  enabled: () => !off("duckduckgo-lite"),
  async search(query, ctx) {
    return parseDuckDuckGoLite(await duckDuckGoPost("https://lite.duckduckgo.com/lite/", query, ctx, this.timeoutMs));
  },
};

const ollama: Provider = {
  name: "ollama",
  role: "web",
  intents: "any",
  timeoutMs: 8_000,
  selfRecorded: true,
  // Off while the Ollama account quota is exhausted (shared with chat): the free engines carry the load.
  enabled: () => !!config.ollamaApiKey && !isQuotaBlocked(OLLAMA_WEB_ID) && !off("ollama"),
  async search(query, ctx) {
    // No retry on 429: the next engine in the chain answers instead.
    const data = await ollamaPost("web_search", { query, max_results: Math.min(ctx.limit, 8) }, ctx.signal, this.timeoutMs).catch((e) => {
      const rateLimited = isRateLimit(e);
      throw new ProviderError(e instanceof OllamaWebError ? e.detail : (e as Error).message, statusOf(e) || (rateLimited ? 429 : 502), rateLimited ? BLOCKED_COOLDOWN_MS : 0);
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

// ---- topical sources -------------------------------------------------------------

const bingNews: Provider = {
  name: "bingnews",
  blockCooldownMs: 5 * 60_000,
  role: "secondary",
  intents: ["news"],
  timeoutMs: 3_500,
  enabled: () => !off("bingnews"),
  async search(query, ctx) {
    const res = await http(`https://www.bing.com/news/search?${bingParams(query, ctx.lang, ctx.region)}`, ctx, this.timeoutMs, { headers: { "User-Agent": BROWSER_UA, Accept: "application/rss+xml, text/xml" } });
    const xml = await res.text();
    if (!/<rss\b/i.test(xml.slice(0, 500))) throw new ProviderError("bing news returned no RSS (bot check?)", 429, BLOCKED_COOLDOWN_MS);
    return parseBingRss(xml, "bingnews");
  },
};

const wikipedia: Provider = {
  name: "wikipedia",
  role: "secondary",
  intents: ["encyclopedic", "academic"],
  timeoutMs: 4_000,
  enabled: () => !off("wikipedia"),
  async search(query, ctx) {
    // Devanagari questions get Hindi Wikipedia (English titles would not match).
    const wiki = ctx.lang === "hi" ? "hi" : "en";
    const qs = new URLSearchParams({
      action: "query", format: "json", generator: "search", gsrsearch: query.replace(/"/g, ""), gsrlimit: "3", gsrnamespace: "0",
      prop: "extracts", exintro: "1", explaintext: "1", exchars: "1800", redirects: "1",
    });
    const data = await json(`https://${wiki}.wikipedia.org/w/api.php?${qs}`, ctx, this.timeoutMs);
    const pages: any[] = Object.values(data?.query?.pages ?? {});
    return pages
      .sort((a, b) => (a.index ?? 0) - (b.index ?? 0))
      .filter((p) => typeof p.extract === "string" && p.extract.length > 60)
      .map((p, rank): Candidate => ({
        title: `${p.title} - Wikipedia`,
        url: `https://${wiki}.wikipedia.org/wiki/${encodeURIComponent(String(p.title).replace(/ /g, "_"))}`,
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
  intents: ["discussion", "repo"],
  timeoutMs: 4_000,
  enabled: () => !off("hackernews"),
  async search(query, ctx) {
    const endpoint = ctx.fresh === "breaking" ? "search_by_date" : "search";
    const qs = new URLSearchParams({ query: query.replace(/"/g, ""), tags: "story", hitsPerPage: "6" });
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
  timeoutMs: 5_000,
  enabled: () => !off("stackexchange"),
  async search(query, ctx) {
    const key: Record<string, string> = config.stackExchangeKey ? { key: config.stackExchangeKey } : {};
    const qs = new URLSearchParams({ order: "desc", sort: "relevance", q: query.replace(/"/g, ""), site: "stackoverflow", accepted: "True", pagesize: "4", ...key });
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
  timeoutMs: 5_000,
  enabled: () => !!config.githubToken && !off("github"),
  async search(query, ctx) {
    const qs = new URLSearchParams({ q: query.replace(/"/g, ""), sort: "stars", order: "desc", per_page: "5" });
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
  timeoutMs: 6_000,
  enabled: () => !off("arxiv"),
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
  enabled: () => config.webSearch.reddit && !off("reddit"),
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
    const qs = new URLSearchParams({ q: query, format: "json", language: ctx.lang ?? (ctx.region ? `en-${ctx.region.toUpperCase()}` : "en"), ...(ctx.fresh === "breaking" ? { time_range: "week" } : {}) });
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

/** Web engines in chain order: a configured free-tier API, then the keyless engines, Ollama (shared quota) last. */
export const PROVIDERS: Provider[] = [brave, duckduckgo, braveHtml, duckduckgoLite, ollama, bingNews, wikipedia, hackerNews, stackExchange, githubRepos, arxiv, reddit, ...searxng];

// ---- runner --------------------------------------------------------------------

export const breaker = new CircuitBreaker({ threshold: 3, cooldownMs: 60_000, maxCooldownMs: 30 * 60_000 });

/** Enabled, not quota-blocked and not circuit-open: worth a request right now. */
export function available(p: Provider): boolean {
  return p.enabled() && breaker.state(p.breakerKey ?? p.name) !== "open";
}

const cache = new TtlLru<Candidate[]>(400);
export const CACHE_TTL_MS: Record<Freshness, number> = { breaking: 3 * 60_000, recent: 30 * 60_000, evergreen: 24 * 60 * 60_000 };
const EMPTY_TTL_MS = 60_000;

export type CallOutcome = { provider: string; candidates: Candidate[]; ms: number; cached?: boolean; skipped?: "circuit"; error?: string };

const inflight = new Map<string, Promise<CallOutcome>>();

/** One provider call: cache (memory, then Postgres), identical in-flight calls shared, circuit breaker, timeout, telemetry. Never throws. */
export function callProvider(p: Provider, rawQuery: string, ctx: SearchCtx): Promise<CallOutcome> {
  // Third-party search engines never see emails, phone numbers, cards or keys.
  const query = redactForExternal(rawQuery);
  const key = searchCacheKey(p.name, ctx.fresh, query, ctx.lang, ctx.region);
  const hit = cache.get(key);
  if (hit) {
    const o = { provider: p.name, candidates: hit, ms: 0, cached: true };
    recordOutcome(o);
    return Promise.resolve(o);
  }
  // Round-table seats and concurrent users asking the same thing share one upstream call.
  const running = inflight.get(key);
  if (running) return running.then((o) => ({ ...o, cached: true, ms: 0 }));
  const run = callUncached(p, query, key, ctx)
    .then((o) => (recordOutcome(o), o))
    .finally(() => inflight.delete(key));
  inflight.set(key, run);
  return run;
}

async function callUncached(p: Provider, query: string, key: string, ctx: SearchCtx): Promise<CallOutcome> {
  const shared = await readPersisted(key);
  if (shared) {
    cache.set(key, shared, shared.length ? CACHE_TTL_MS[ctx.fresh] : EMPTY_TTL_MS);
    return { provider: p.name, candidates: shared, ms: 0, cached: true };
  }
  const circuit = p.breakerKey ?? p.name;
  if (!breaker.allow(circuit)) return { provider: p.name, candidates: [], ms: 0, skipped: "circuit" };
  const started = Date.now();
  try {
    const candidates = (await p.search(query, ctx)).slice(0, ctx.limit);
    const ms = Date.now() - started;
    breaker.success(circuit);
    const ttl = candidates.length ? CACHE_TTL_MS[ctx.fresh] : EMPTY_TTL_MS;
    cache.set(key, candidates, ttl);
    if (candidates.length) writePersisted(key, candidates, ttl);
    if (!p.selfRecorded) recordUsage({ provider: "web", model: p.name, kind: "search", ok: true, status: 200, latencyMs: ms, count: candidates.length });
    return { provider: p.name, candidates, ms };
  } catch (e) {
    const ms = Date.now() - started;
    if (ctx.signal?.aborted) return { provider: p.name, candidates: [], ms, error: "aborted" };
    const status = e instanceof ProviderError ? e.status : statusOf(e);
    const retryAfterMs = (e instanceof ProviderError ? e.retryAfterMs : 0) || (status === 429 ? (p.blockCooldownMs ?? 0) : 0);
    const timedOut = (e as Error)?.name === "TimeoutError" || /timed? ?out/i.test((e as Error)?.message ?? "");
    // 4xx other than 429 on a search request is our problem or a block, not an outage: only 401/403 trips at once.
    // A 429 with a long cooldown (an engine's bot check, an exhausted quota) also opens at once: retrying it only burns time.
    const countable = status === 0 || status === 429 || status >= 500 || timedOut;
    // Any 429 means "slow down": the engine is left alone for a while at once instead of being asked again until it trips.
    if (status === 429) breaker.failure(circuit, { hard: true, retryAfterMs: Math.max(retryAfterMs, RATE_LIMIT_COOLDOWN_MS) });
    else if (status === 401 || status === 403) breaker.failure(circuit, { hard: true, retryAfterMs });
    else if (countable) breaker.failure(circuit, { retryAfterMs });
    if (!p.selfRecorded) {
      recordUsage({ provider: "web", model: p.name, kind: "search", ok: false, status: status || undefined, latencyMs: ms, errorMessage: timedOut ? "timeout" : (e as Error).message });
    }
    log.warn("web provider failed", { provider: p.name, status, message: (e as Error).message?.slice(0, 100), circuit: breaker.state(circuit) });
    return { provider: p.name, candidates: [], ms, error: timedOut ? "timeout" : status ? `http_${status}` : "error" };
  }
}

/** Test hook: forget cached provider results. */
export function clearProviderCache(): void {
  cache.clear();
  inflight.clear();
}
