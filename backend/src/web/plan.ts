// Query planning: turn the user's message (plus conversation context for
// follow-ups) into 1-3 focused search queries, a freshness class and the
// intents that decide which sources to ask. A cheap model does the rewrite
// when the message needs it; a heuristic is always the fallback.

import type { Message } from "../providers.js";
import { ask } from "../llm/ask.js";
import { pickCandidates } from "../llm/router.js";
import { log } from "../util/logger.js";
import { needsFreshFacts } from "./freshness.js";
import type { Freshness, Intent } from "./types.js";

export type SearchPlan = { queries: string[]; fresh: Freshness; intents: Intent[]; via: "heuristic" | "model" };
export type PlanContext = { previousUser?: string; previousAssistant?: string };

const PLAN_MODELS = ["groq:openai/gpt-oss-20b", "ollama:gpt-oss:20b"];
const PLAN_MS = 2_500;
const MAX_QUERY = 160;

const BREAKING = /\b(breaking|today|tonight|right now|just (released|announced)|live|this (morning|evening)|yesterday|news|headlines?|scores?|score of|weather|stock price)\b/i;
const FILLER = /^(?:hey|hi|hello|ok(?:ay)?|so|please|pls|kindly)[,.!\s]+|^(?:can|could|would|will) you (?:please )?(?:tell me|find|search(?: for)?|look up|check|google|explain)\s+|^(?:i (?:want|need|would like) to (?:know|find out)|tell me|let me know|find me|search for|look up|google)\s+(?:about\s+)?/i;
const FOLLOW_UP = /^(?:and|but|also|what about|how about|then|so|why|how|what|where|when|who|which|is|are|does|do|did|can|could)\b[^.?!]{0,60}\b(it|its|that|this|they|them|those|these|he|she|there|one|the same)\b|^(?:and|also|what about|how about|more|why|and then)\b/i;

const stripFiller = (s: string) => s.replace(FILLER, "").replace(FILLER, "");
const clean = (s: string) => s.replace(/https?:\/\/\S+/g, " ").replace(/\s+/g, " ").trim();

export function classifyFreshness(text: string): Freshness {
  if (BREAKING.test(text)) return "breaking";
  return needsFreshFacts(text) ? "recent" : "evergreen";
}

export function detectIntents(text: string): Intent[] {
  const out: Intent[] = [];
  if (BREAKING.test(text) || /\b(news|announce\w*|release[sd]?|launch\w*|changelog|roadmap)\b/i.test(text)) out.push("news");
  if (/\b(error|exception|stack ?trace|bug|compile|install|config(?:ure)?|syntax|regex|api|sdk|python|javascript|typescript|dart|flutter|rust|golang|java|kotlin|swift|c\+\+|sql|css|html|react|node(?:js)?|docker|npm|pip|git|linux|bash|postgres|prisma|express)\b/i.test(text)) out.push("code");
  if (/\b(libraries|library|package|framework|repo(?:sitory)?|github|open[- ]?source|sdk|cli tool|alternatives? to)\b/i.test(text)) out.push("repo");
  if (/\b(paper|arxiv|study|studies|research|algorithm|theorem|neural|transformer|llm|survey|benchmark|retrieval|embedding|proof)\b/i.test(text)) out.push("academic");
  if (/\b(best|vs\.?|versus|opinions?|reviews?|worth it|recommend\w*|experience|reddit|discussion|pros and cons)\b/i.test(text)) out.push("discussion");
  if (/^(?:what (?:is|are|was|were)|who (?:is|was)|when (?:did|was)|where (?:is|was)|define|explain|history of|how does|how do)\b/i.test(text) || out.length === 0) out.push("encyclopedic");
  return [...new Set(out)];
}

/** Heuristic rewrite: strip chit-chat and URLs, carry the topic over for short follow-ups. */
export function heuristicQueries(question: string, ctx: PlanContext = {}, now = new Date()): string[] {
  let q = stripFiller(clean(question)).replace(/[?!.]+$/, "").trim();
  if (!q) q = clean(question);
  const words = q.split(/\s+/).filter(Boolean);
  const followUp = words.length < 4 || (words.length < 9 && FOLLOW_UP.test(q));
  if (followUp && ctx.previousUser) {
    const topic = stripFiller(clean(ctx.previousUser)).replace(/[?!.]+$/, "");
    if (topic) q = `${topic.split(/\s+/).slice(0, 12).join(" ")} ${q}`;
  }
  q = q.slice(0, MAX_QUERY);
  const queries = [q];
  const fresh = classifyFreshness(q);
  if (fresh !== "evergreen" && !/\b20\d\d\b/.test(q) && words.length <= 10) queries.push(`${q} ${now.getFullYear()}`);
  return dedupeQueries(queries);
}

const norm = (q: string) => q.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
export function dedupeQueries(qs: string[], max = 3): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of qs) {
    const q = raw.replace(/\s+/g, " ").trim().slice(0, MAX_QUERY);
    if (!q || seen.has(norm(q))) continue;
    seen.add(norm(q));
    out.push(q);
    if (out.length >= max) break;
  }
  return out;
}

const PROMPT = `You rewrite a chat message into web search queries.
Return only JSON: {"queries": ["..."], "fresh": "breaking" | "recent" | "evergreen"}
- 1 to 3 queries, each 3-10 words, keyword style, no quotes or operators, no filler.
- Resolve pronouns and follow-ups using the earlier messages so each query stands alone.
- The first query is the main one; extra queries cover a different angle or wording.
- fresh: "breaking" for news in the last days, "recent" if facts change over months (versions, prices, releases), else "evergreen".`;

export function parsePlan(raw: string): { queries: string[]; fresh?: Freshness } | null {
  try {
    const j = JSON.parse(raw.slice(raw.indexOf("{"), raw.lastIndexOf("}") + 1)) as { queries?: unknown; fresh?: unknown };
    const queries = Array.isArray(j.queries) ? j.queries.filter((q): q is string => typeof q === "string") : [];
    if (!queries.length) return null;
    const fresh = j.fresh === "breaking" || j.fresh === "recent" || j.fresh === "evergreen" ? j.fresh : undefined;
    return { queries, fresh };
  } catch {
    return null;
  }
}

/** Whether the message is worth a model call: a follow-up, or long and rambling. */
export function needsModel(question: string, ctx: PlanContext): boolean {
  const q = clean(question);
  const words = q.split(/\s+/).length;
  if (q.length > 160) return true;
  return !!ctx.previousUser && (words < 4 || (words < 9 && FOLLOW_UP.test(q)));
}

/**
 * The plan for one search. [focused] is a query already written for search
 * (from the search decision); it is used as the main query without a model call.
 */
export async function planSearch(question: string, ctx: PlanContext, signal?: AbortSignal, focused?: string): Promise<SearchPlan> {
  const intents = detectIntents(`${focused ?? ""} ${question}`);
  if (focused) {
    const queries = dedupeQueries([focused, ...heuristicQueries(focused, ctx).slice(1)]);
    return { queries, fresh: classifyFreshness(`${focused} ${question}`), intents, via: "heuristic" };
  }
  const base = heuristicQueries(question, ctx);
  const fresh = classifyFreshness(question);
  if (!needsModel(question, ctx)) return { queries: base, fresh, intents, via: "heuristic" };
  try {
    const avail = new Set(await pickCandidates(undefined));
    const model = PLAN_MODELS.find((m) => avail.has(m));
    if (model && !signal?.aborted) {
      const messages: Message[] = [
        { role: "system", content: `${PROMPT}\nToday's date is ${new Date().toISOString().slice(0, 10)}.` },
        {
          role: "user",
          content: `${ctx.previousUser ? `Earlier user message: ${ctx.previousUser.slice(0, 400)}\n` : ""}${ctx.previousAssistant ? `Earlier assistant reply: ${ctx.previousAssistant.slice(0, 400)}\n` : ""}Latest message: ${question.slice(0, 1200)}`,
        },
      ];
      const raw = await ask(model, messages, { timeoutMs: PLAN_MS, maxTokens: 600, signal, purpose: "search-plan" });
      const plan = parsePlan(raw);
      if (plan) {
        const queries = dedupeQueries(plan.queries);
        const f = plan.fresh ?? fresh;
        return { queries, fresh: f, intents: detectIntents(`${queries.join(" ")} ${question}`), via: "model" };
      }
    }
  } catch (e) {
    if (!signal?.aborted) log.warn("search plan failed", { message: (e as Error).message?.slice(0, 100) });
  }
  return { queries: base, fresh, intents, via: "heuristic" };
}
