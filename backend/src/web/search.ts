// Public entry points for web search. The work is done by the pipeline
// (query planning, provider chain with circuit breakers, ranking, passage
// extraction); see pipeline.ts and providers.ts.

import { assertPublicUrl } from "../ingest/fetcher.js";
import { isQuotaBlocked } from "../llm/quota.js";
import { recordUsage } from "../db/usage.js";
import { clip, OLLAMA_WEB_ID, ollamaPost } from "./ollama.js";
import { fetchPage, researchWeb } from "./pipeline.js";
import { selectPassages } from "./passages.js";
import { breaker } from "./providers.js";
import { hostOf } from "./url.js";
import type { WebResult } from "./types.js";
import { config } from "../config.js";

export type { WebResult } from "./types.js";
export { researchWeb } from "./pipeline.js";
export { webStats } from "./stats.js";

/**
 * Single-angle search for an already focused query (Round Table seats):
 * no query rewriting, one query, one page read.
 */
export function webSearch(query: string, signal?: AbortSignal): Promise<WebResult[]> {
  return researchWeb({ question: query, focused: query, signal, maxQueries: 1, fetchTop: 1 });
}

/** Jina's keyless reader: renders script-heavy pages the local fetch cannot read. */
async function jinaRead(url: string, signal?: AbortSignal): Promise<{ title: string; text: string } | null> {
  if (config.webSearch.disabled.has("jina") || breaker.state("jina") === "open") return null;
  await assertPublicUrl(url);
  const started = Date.now();
  try {
    const res = await fetch(`https://r.jina.ai/${url}`, {
      headers: { Accept: "text/plain", "X-Return-Format": "markdown" },
      signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(8_000)]) : AbortSignal.timeout(8_000),
    });
    if (!res.ok) {
      if (res.status === 429 || res.status >= 500) breaker.failure("jina", { retryAfterMs: res.status === 429 ? 10 * 60_000 : 0 });
      recordUsage({ provider: "web", model: "jina", kind: "fetch", ok: false, status: res.status, latencyMs: Date.now() - started });
      return null;
    }
    const body = await res.text();
    breaker.success("jina");
    recordUsage({ provider: "web", model: "jina", kind: "fetch", ok: true, status: res.status, latencyMs: Date.now() - started });
    const title = body.match(/^Title:\s*(.+)$/m)?.[1]?.trim() ?? "";
    const text = (body.split(/^Markdown Content:\s*$/m)[1] ?? body).trim();
    return text.length >= 200 ? { title, text } : null;
  } catch (e) {
    if (!signal?.aborted) recordUsage({ provider: "web", model: "jina", kind: "fetch", ok: false, latencyMs: Date.now() - started, errorMessage: (e as Error).message });
    return null;
  }
}

const toResult = (url: string, page: { title: string; text: string }): WebResult => ({
  title: clip(page.title, 200) || hostOf(url) || url,
  url,
  content: selectPassages(page.text, "", { maxChars: 2500, maxPassages: 6, passageLen: 700 }),
  full: page.text.slice(0, 12_000),
  site: hostOf(url),
});

/** Reads one URL: the local readability fetch first, then Jina's reader, then Ollama's fetch (only while its quota lasts). */
export async function webFetch(url: string, signal?: AbortSignal): Promise<WebResult | null> {
  const page = await fetchPage(url, signal, 8_000);
  if (page) return toResult(url, page);
  const jina = await jinaRead(url, signal).catch(() => null);
  if (jina) return toResult(url, jina);
  if (!config.ollamaApiKey || isQuotaBlocked(OLLAMA_WEB_ID)) return null;
  const data = await ollamaPost("web_fetch", { url }, signal);
  const content = clip(data?.content, 2500);
  return content ? { title: clip(data?.title, 200) || url, url, content, full: clip(data?.content, 12_000), site: hostOf(url) } : null;
}
