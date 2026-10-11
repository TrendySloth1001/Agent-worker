import { streamModel, type Message } from "../providers.js";
import { log } from "../util/logger.js";
import { needsFreshFacts } from "./freshness.js";

export type SearchDecision = { search: boolean; query: string; reason: "explicit" | "fresh" | "model" | "none" };

/** The user explicitly asks for the web. */
const EXPLICIT = /\b(search|google|look ?up|browse|find (me )?(sources?|links?|articles?|references?)|check (online|the web|the internet)|on the (web|internet)|cite sources?|with sources)\b/i;

const PROMPT = `You decide whether answering the user's latest message needs a live web search.
Search when the answer depends on: recent or changing information (news, prices, versions, releases, schedules, who currently holds a role), specific facts about named products, companies, people, places, papers or events that a well-read assistant may not know precisely, statistics or figures, or when the user wants sources or links.
Do NOT search for: coding help, debugging, explaining well-established concepts, math, writing or editing text, brainstorming, opinions, the user's own data or files, greetings, or follow-ups answerable from the conversation.
Reply with only JSON: {"search": true or false, "query": "<a focused web search query of 3-10 words, or empty>"}`;

const MODELS = ["groq:openai/gpt-oss-20b", "ollama:gpt-oss:20b"];
const TIMEOUT_MS = 4_000;
const cache = new Map<string, SearchDecision>();

async function askModel(model: string, messages: Message[]): Promise<string> {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), TIMEOUT_MS);
  try {
    const handle = await streamModel(model, messages, { signal: ctl.signal, firstByteMs: TIMEOUT_MS, idleMs: TIMEOUT_MS });
    let text = "";
    for await (const t of handle.tokens) text += t;
    return text;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Whether this turn needs the web, and what to search for. Explicit requests
 * and clearly time-sensitive questions search without asking a model;
 * everything else is decided by a small fast model. Never throws.
 */
export async function decideSearch(question: string, previous: string): Promise<SearchDecision> {
  const q = question.trim();
  if (!q) return { search: false, query: "", reason: "none" };
  if (EXPLICIT.test(q)) return { search: true, query: q.slice(0, 200), reason: "explicit" };
  // "this month" in "my metrics for this month: revenue 12400" is the user's own
  // data, not news: let the model decide those instead of the fast path.
  const ownData = /\b(my|our|mine|we have|i have|i got|we got)\b/i.test(q) && /\d/.test(q);
  if (!ownData && needsFreshFacts(q)) return { search: true, query: q.slice(0, 200), reason: "fresh" };
  const key = `${previous.slice(-200)}|${q}`.toLowerCase();
  const hit = cache.get(key);
  if (hit) return hit;

  const messages: Message[] = [
    { role: "system", content: PROMPT },
    { role: "user", content: `${previous ? `Previous assistant message (for context): ${previous.slice(0, 600)}\n\n` : ""}Latest user message: ${q.slice(0, 1200)}` },
  ];
  let decision: SearchDecision = { search: false, query: "", reason: "none" };
  for (const model of MODELS) {
    try {
      const raw = await askModel(model, messages);
      const json = raw.slice(raw.indexOf("{"), raw.lastIndexOf("}") + 1);
      const parsed = JSON.parse(json) as { search?: unknown; query?: unknown };
      decision = {
        search: parsed.search === true,
        query: typeof parsed.query === "string" && parsed.query.trim() ? parsed.query.trim().slice(0, 200) : q.slice(0, 200),
        reason: parsed.search === true ? "model" : "none",
      };
      break;
    } catch (e) {
      log.warn("search decision failed", { model, message: (e as Error).message?.slice(0, 100) });
    }
  }
  cache.set(key, decision);
  if (cache.size > 500) cache.delete(cache.keys().next().value as string);
  return decision;
}
