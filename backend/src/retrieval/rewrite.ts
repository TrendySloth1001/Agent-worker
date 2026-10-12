import { log } from "../util/logger.js";
import { askSmall, extractJson, SMALL_MODELS } from "./smallModel.js";

export type HistoryMsg = { role: string; content: string };

const TIMEOUT_MS = 2_500;
const cache = new Map<string, string[]>();

const PROMPT = `You rewrite the latest user message into standalone search queries for a knowledge base.
Resolve pronouns and references ("it", "that", "the second one", "what about X?") using the conversation.
Return 1 to 3 short queries (3-14 words each) covering different phrasings or sub-questions. Keep names, numbers and code identifiers exactly.
Reply with only JSON: {"queries": ["...", "..."]}`;

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
 * Standalone query variants for [query], resolved against recent [history]
 * (which ends with [query] itself or not). Never throws; returns [] when no
 * rewrite is needed or the small model is slow/unavailable.
 */
export async function rewriteQueries(query: string, history: HistoryMsg[]): Promise<string[]> {
  const recent = history.slice(-6);
  if (!needsRewrite(query, recent)) return [];
  const key = `${recent.slice(-3).map((m) => m.content.slice(0, 120)).join("|")}#${query}`.toLowerCase();
  const hit = cache.get(key);
  if (hit) return hit;
  const convo = recent.map((m) => `${m.role === "user" ? "User" : "Assistant"}: ${m.content.replace(/\s+/g, " ").slice(0, 400)}`).join("\n");
  const messages = [
    { role: "system" as const, content: PROMPT },
    { role: "user" as const, content: `Conversation:\n${convo}\n\nLatest user message: ${query.slice(0, 600)}` },
  ];
  let out: string[] = [];
  for (const model of SMALL_MODELS) {
    try {
      const raw = await askSmall(model, messages, "kb-rewrite", TIMEOUT_MS);
      const parsed = extractJson(raw, "{") as { queries?: unknown };
      if (Array.isArray(parsed.queries)) {
        out = parsed.queries.filter((q): q is string => typeof q === "string").map((q) => q.trim().slice(0, 300)).filter((q) => q.length >= 3);
        out = [...new Set(out)].filter((q) => q.toLowerCase() !== query.trim().toLowerCase()).slice(0, 3);
      }
      break;
    } catch (e) {
      log.warn("query rewrite failed", { model, message: (e as Error).message?.slice(0, 100) });
    }
  }
  cache.set(key, out);
  if (cache.size > 300) cache.delete(cache.keys().next().value as string);
  return out;
}
