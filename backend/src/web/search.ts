import { config } from "../config.js";
import { AppError } from "../util/errors.js";
import { recordUsage } from "../db/usage.js";

/** `content` is the short snippet given to the model; `full` is the longer
 * page text kept only for matching citations to their supporting passage. */
export type WebResult = { title: string; url: string; content: string; full?: string };

const TTL_MS = 10 * 60_000;
const MAX_ENTRIES = 100;
const cache = new Map<string, { at: number; value: WebResult[] }>();

function cacheGet(key: string) {
  const hit = cache.get(key);
  if (!hit) return null;
  if (Date.now() - hit.at > TTL_MS) {
    cache.delete(key);
    return null;
  }
  cache.delete(key); // refresh LRU position
  cache.set(key, hit);
  return hit.value;
}

function cacheSet(key: string, value: WebResult[]) {
  cache.set(key, { at: Date.now(), value });
  while (cache.size > MAX_ENTRIES) cache.delete(cache.keys().next().value as string);
}

async function ollamaPost(path: "web_search" | "web_fetch", body: object, signal?: AbortSignal) {
  if (!config.ollamaApiKey) throw new AppError(503, "unavailable", "Web search is not configured");
  const kind = path === "web_search" ? "search" : "fetch";
  const started = Date.now();
  let status = 0;
  try {
    const res = await fetch(`https://ollama.com/api/${path}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${config.ollamaApiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(15_000)]) : AbortSignal.timeout(15_000),
    });
    status = res.status;
    if (!res.ok) throw new AppError(502, "upstream_failed", `${path} failed (${res.status})`, res.status === 429 || res.status >= 500);
    const data = await res.json();
    recordUsage({ provider: "ollama", kind, ok: true, status, latencyMs: Date.now() - started });
    return data as any;
  } catch (e) {
    if (!(e instanceof AppError) || status) recordUsage({ provider: "ollama", kind, ok: false, status: status || undefined, latencyMs: Date.now() - started });
    if (e instanceof AppError) throw e;
    throw new AppError(502, "upstream_failed", `${path} failed: ${(e as Error).message}`, true);
  }
}

const clip = (s: unknown, n: number) => (typeof s === "string" ? s.slice(0, n) : "");

const sleep = (ms: number, signal?: AbortSignal) =>
  new Promise<void>((resolve, reject) => {
    const t = setTimeout(resolve, ms);
    signal?.addEventListener("abort", () => (clearTimeout(t), reject(signal.reason)), { once: true });
  });

const isRateLimit = (e: unknown) => e instanceof AppError && /\(429\)/.test(e.message);

/** Ollama web search; on a rate limit (429) backs off and retries twice. */
export async function webSearch(query: string, signal?: AbortSignal): Promise<WebResult[]> {
  const key = `s:${query.toLowerCase()}`;
  const cached = cacheGet(key);
  if (cached) return cached;
  let data: any;
  try {
    data = await ollamaPost("web_search", { query, max_results: 5 }, signal);
  } catch (e) {
    if (!isRateLimit(e)) throw e;
    try {
      await sleep(1200 + Math.random() * 800, signal);
      data = await ollamaPost("web_search", { query, max_results: 5 }, signal);
    } catch (e2) {
      if (!isRateLimit(e2)) throw e2;
      await sleep(2500 + Math.random() * 1000, signal);
      data = await ollamaPost("web_search", { query, max_results: 5 }, signal);
    }
  }
  const results: WebResult[] = (Array.isArray(data?.results) ? data.results : [])
    .filter((r: any) => typeof r?.url === "string")
    .slice(0, 5)
    .map((r: any) => ({ title: clip(r.title, 200) || r.url, url: r.url, content: clip(r.content, 1500), full: clip(r.content, 12_000) }));
  cacheSet(key, results);
  return results;
}

export async function webFetch(url: string, signal?: AbortSignal): Promise<WebResult | null> {
  const key = `f:${url}`;
  const cached = cacheGet(key);
  if (cached) return cached[0] ?? null;
  const data = await ollamaPost("web_fetch", { url }, signal);
  const content = clip(data?.content, 2500);
  const result = content ? { title: clip(data?.title, 200) || url, url, content, full: clip(data?.content, 12_000) } : null;
  cacheSet(key, result ? [result] : []);
  return result;
}
