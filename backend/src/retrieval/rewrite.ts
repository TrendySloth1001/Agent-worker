import { log } from "../util/logger.js";
import { askSmall, extractJson, SMALL_MODELS } from "./smallModel.js";

export type HistoryMsg = { role: string; content: string };

const TIMEOUT_MS = 2_500;
export type Rewrite = { /** The message as one self-contained question. */ standalone: string; /** Extra search phrasings (0-3). */ queries: string[]; /** How it was produced. */ via: "none" | "model" | "heuristic" };
const cache = new Map<string, Rewrite>();

const PROMPT = `You rewrite the latest user message into a standalone question and standalone search queries for a knowledge base.
Resolve pronouns and references ("it", "that", "the second one", "what about X?") using the conversation.
"standalone" is the whole message as one self-contained question (keep its language). "queries" are 1 to 3 short queries (3-14 words each) covering different phrasings or sub-questions. Keep names, numbers and code identifiers exactly.
Reply with only JSON: {"standalone": "...", "queries": ["...", "..."]}`;

const REFERENTIAL = /\b(it|its|this|that|these|those|they|them|their|he|she|there|here|the (above|previous|last|same|first|second|third|other)|above|earlier|before|again|also|more|another|else|instead|too)\b/i;

/**
 * Whether the message likely depends on the conversation to be understood.
 * Standalone, specific questions skip the model call entirely.
 */
export function needsRewrite(query: string, history: HistoryMsg[]): boolean {
  if (!history.some((m) => m.role === "assistant")) return false;
  const q = query.trim();
  if (!q) return false;
  const words = q.split(/\s+/).length;
  if (words <= 6) return true;
  return words <= 24 && REFERENTIAL.test(q);
}

/**
 * Heuristic standalone form of a referential message, used when the small model
 * is slow or unavailable: the topic of the previous user message (or the given
 * [topics]) is carried over. Standalone messages are returned unchanged.
 */
export function heuristicStandalone(query: string, history: HistoryMsg[], topics: string[] = []): string {
  const q = query.trim();
  if (!needsRewrite(q, history)) return q;
  const prev = [...history].reverse().filter((m) => m.role === "user" && m.content.trim() && m.content.trim() !== q)[0]?.content.replace(/\s+/g, " ").trim();
  const head = prev ? prev.replace(/[?!.]+$/, "").split(" ").slice(0, 14).join(" ") : topics.slice(0, 3).join(" ");
  if (!head) return q;
  // Already mentions the topic: nothing to add.
  if (head.toLowerCase().split(" ").filter((w) => w.length > 3).some((w) => q.toLowerCase().includes(w)) && q.split(/\s+/).length > 6) return q;
  return `${head} - ${q}`.slice(0, 500);
}

/**
 * The standalone question and query variants for [query], resolved against
 * recent [history]. Never throws. Without a rewrite (query already standalone)
 * the original is returned with no variants; when the model is slow or down,
 * the standalone form comes from [heuristicStandalone].
 */
export async function rewriteTurn(query: string, history: HistoryMsg[], opts: { topics?: string[]; timeoutMs?: number } = {}): Promise<Rewrite> {
  const recent = history.slice(-6);
  if (!needsRewrite(query, recent)) return { standalone: query.trim(), queries: [], via: "none" };
  const key = `${recent.slice(-3).map((m) => m.content.slice(0, 120)).join("|")}#${query}`.toLowerCase();
  const hit = cache.get(key);
  if (hit) return hit;
  const convo = recent.map((m) => `${m.role === "user" ? "User" : "Assistant"}: ${m.content.replace(/\s+/g, " ").slice(0, 400)}`).join("\n");
  const messages = [
    { role: "system" as const, content: PROMPT },
    { role: "user" as const, content: `Conversation:\n${convo}\n\nLatest user message: ${query.slice(0, 600)}` },
  ];
  let out: Rewrite | null = null;
  const deadline = Date.now() + (opts.timeoutMs ?? TIMEOUT_MS);
  for (const model of SMALL_MODELS) {
    const left = deadline - Date.now();
    if (left < 400) break;
    try {
      const raw = await askSmall(model, messages, "kb-rewrite", left);
      const parsed = extractJson(raw, "{") as { standalone?: unknown; queries?: unknown };
      let queries: string[] = [];
      if (Array.isArray(parsed.queries)) {
        queries = parsed.queries.filter((q): q is string => typeof q === "string").map((q) => q.trim().slice(0, 300)).filter((q) => q.length >= 3);
        queries = [...new Set(queries)].filter((q) => q.toLowerCase() !== query.trim().toLowerCase()).slice(0, 3);
      }
      const standalone = typeof parsed.standalone === "string" && parsed.standalone.trim().length >= 3 ? parsed.standalone.trim().slice(0, 500) : "";
      out = { standalone: standalone || queries[0] || heuristicStandalone(query, recent, opts.topics), queries, via: "model" };
      break;
    } catch (e) {
      log.warn("query rewrite failed", { model, message: (e as Error).message?.slice(0, 100) });
    }
  }
  // Failures are not cached: the next turn may find the model back.
  if (!out) return { standalone: heuristicStandalone(query, recent, opts.topics), queries: [], via: "heuristic" };
  cache.set(key, out);
  if (cache.size > 300) cache.delete(cache.keys().next().value as string);
  return out;
}

/**
 * Standalone query variants for [query], resolved against recent [history].
 * Never throws; returns [] when no rewrite is needed or the small model is slow/unavailable.
 */
export async function rewriteQueries(query: string, history: HistoryMsg[]): Promise<string[]> {
  return (await rewriteTurn(query, history)).queries;
}
