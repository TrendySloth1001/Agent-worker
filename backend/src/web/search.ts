// Public entry points for web search. The work is done by the pipeline
// (query planning, provider chain with circuit breakers, ranking, passage
// extraction); see pipeline.ts and providers.ts.

import { clip, ollamaPost } from "./ollama.js";
import { fetchPage, researchWeb } from "./pipeline.js";
import { selectPassages } from "./passages.js";
import type { WebResult } from "./types.js";

export type { WebResult } from "./types.js";
export { researchWeb } from "./pipeline.js";

/**
 * Single-angle search for an already focused query (Round Table seats):
 * no query rewriting, one query, a couple of pages read.
 */
export function webSearch(query: string, signal?: AbortSignal): Promise<WebResult[]> {
  return researchWeb({ question: query, focused: query, signal, maxQueries: 1, fetchTop: 2 });
}

/** Reads one URL: the local readability fetch first, Ollama's fetch as a fallback for blocked or script-rendered pages. */
export async function webFetch(url: string, signal?: AbortSignal): Promise<WebResult | null> {
  const page = await fetchPage(url, signal, 8_000);
  if (page) return { title: clip(page.title, 200) || url, url, content: selectPassages(page.text, "", { maxChars: 2500, maxPassages: 6, passageLen: 700 }), full: page.text.slice(0, 12_000) };
  const data = await ollamaPost("web_fetch", { url }, signal);
  const content = clip(data?.content, 2500);
  return content ? { title: clip(data?.title, 200) || url, url, content, full: clip(data?.content, 12_000) } : null;
}
