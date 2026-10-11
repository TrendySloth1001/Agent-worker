// Per-seat web research for Round Table: one cheap planning call turns the
// question into up to three search angles (one per seat), then every angle
// is searched in parallel through the normal web search.

import type { Message } from "../providers.js";
import { ask } from "../llm/ask.js";
import { pickCandidates } from "../llm/router.js";
import { webSearch, type WebResult } from "../web/search.js";
import { log } from "../util/logger.js";
import { RESEARCH_PLAN_PROMPT } from "../prompts/table.js";
import { recordLatency } from "./latency.js";

export type SeatResearch = { seat: "A" | "B" | "C"; queries: string[]; results: WebResult[] };

const SEATS = ["A", "B", "C"] as const;
const PLAN_MODELS = ["groq:openai/gpt-oss-20b", "ollama:gpt-oss:20b"];
const PLAN_MS = 5_000;
const PLAN_TOKENS = 1_200;
const SEARCH_MS = 12_000;
const STAGGER_MS = 600;
const PER_SEAT = 4;
/** Seat results are shorter than shared ones so the chair's prompt stays small. */
const SEAT_SNIPPET = 900;
const QUERY_MAX = 120;

const norm = (q: string) => q.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();

/** Fallback angles when the planner is unavailable. */
function deterministic(base: string): string[] {
  const year = new Date().getFullYear();
  return [`${base} official source`, `${base} latest ${year}`, `${base} analysis`];
}

/** Up to three distinct queries, different from `base` (already searched). */
export async function planQueries(question: string, base: string, signal: AbortSignal): Promise<string[]> {
  const started = Date.now();
  const avail = new Set(await pickCandidates(undefined));
  const messages: Message[] = [
    { role: "system", content: `${RESEARCH_PLAN_PROMPT}\nToday's date is ${new Date().toISOString().slice(0, 10)}.` },
    { role: "user", content: `Question: ${question.slice(0, 1200)}\nBase query (already searched): ${base}` },
  ];
  let planned: string[] = [];
  for (const model of PLAN_MODELS.filter((m) => avail.has(m))) {
    if (signal.aborted) break;
    try {
      const raw = await ask(model, messages, { timeoutMs: PLAN_MS, maxTokens: PLAN_TOKENS, signal, purpose: "table-research" });
      const json = JSON.parse(raw.slice(raw.indexOf("{"), raw.lastIndexOf("}") + 1)) as { queries?: unknown };
      if (Array.isArray(json.queries)) planned = json.queries.filter((q): q is string => typeof q === "string");
      if (planned.length) break;
    } catch (e) {
      if (signal.aborted) break;
      log.warn("table research plan failed", { model, message: (e as Error).message?.slice(0, 100) });
    }
  }
  const seen = new Set([norm(base)]);
  const out: string[] = [];
  for (const q of [...planned, ...deterministic(base)]) {
    const clean = q.replace(/\s+/g, " ").trim().slice(0, QUERY_MAX);
    if (!clean || seen.has(norm(clean))) continue;
    seen.add(norm(clean));
    out.push(clean);
    if (out.length === SEATS.length) break;
  }
  recordLatency("research", "plan", Date.now() - started);
  return out;
}

/** Searches each seat's query (staggered starts); a failed or slow search leaves that seat with none. */
export async function runSeatResearch(queries: string[], signal: AbortSignal): Promise<SeatResearch[]> {
  const started = Date.now();
  const settled = await Promise.allSettled(
    // Staggered starts: three searches in the same instant trip Ollama's rate limit.
    queries.slice(0, SEATS.length).map(async (q, i) => {
      if (i > 0) await new Promise((r) => setTimeout(r, i * STAGGER_MS));
      return webSearch(q, AbortSignal.any([signal, AbortSignal.timeout(SEARCH_MS)]));
    }),
  );
  recordLatency("research", "search", Date.now() - started);
  settled.forEach((r, i) => {
    if (r.status === "rejected") log.warn("table seat search failed", { seat: SEATS[i], message: String((r.reason as Error)?.message ?? r.reason).slice(0, 120) });
  });
  return settled.map((r, i) => ({
    seat: SEATS[i],
    // A failed search is not shown as research the seat did.
    queries: r.status === "fulfilled" ? [queries[i]] : [],
    results: r.status === "fulfilled" ? r.value.slice(0, PER_SEAT).map((w) => ({ ...w, content: w.content.slice(0, SEAT_SNIPPET) })) : [],
  }));
}
