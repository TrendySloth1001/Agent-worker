// The turn preflight: ONE small, fast model call that replaces what used to be
// three or four (standalone rewrite, search decision, web query plan, RAG
// query variants). It returns
//   {standalone, needsWeb, freshness, queries[], needsKb, pastRef}
// and is skipped entirely when the local NLP and heuristics are confident.
// Time-boxed; on any failure a heuristic preflight is returned, so a turn never
// waits on it for more than PREFLIGHT_MS.
import { askSmall, extractJson, SMALL_MODELS } from "../retrieval/smallModel.js";
import { heuristicStandalone, needsRewrite, type HistoryMsg } from "../retrieval/rewrite.js";
import { classifyFreshness, heuristicQueries } from "../web/plan.js";
import type { SearchDecision } from "../web/searchDecision.js";
import type { Freshness } from "../web/types.js";
import type { Message } from "../providers.js";
import { log } from "../util/logger.js";

export const PREFLIGHT_MS = 2_500;
const MAX_QUERIES = 2;

export type Preflight = {
  /** The latest message as one self-contained question. */
  standalone: string;
  /** Whether the answer needs a live web search (null: not asked). */
  needsWeb: boolean | null;
  freshness: Freshness | null;
  /** 1-2 search queries (also used as knowledge-base variants). */
  queries: string[];
  /** Whether the knowledge base is worth searching (null: not asked). */
  needsKb: boolean | null;
  /** The user refers to an earlier conversation. */
  pastRef: boolean | null;
  via: "model" | "heuristic";
};

export type PreflightInput = {
  text: string;
  history: HistoryMsg[];
  /** Names the chat has been about, for the heuristic fallback. */
  topics?: string[];
  wantWeb: boolean;
  /** The decision the local rules already made (null: uncertain). */
  webLocal: SearchDecision | null;
};

export type AskSmallFn = (model: string, messages: Message[], purpose: string, timeoutMs: number, opts?: { maxTokens?: number; reasoningEffort?: "low" }) => Promise<string>;

/** What the local rules cannot settle, so the model has to be asked. All false means: no call. */
export function preflightNeeds(i: Pick<PreflightInput, "text" | "history" | "wantWeb" | "webLocal"> & { /** Confident small talk ("thanks!"): nothing to resolve or search. */ smallTalk?: boolean }): { rewrite: boolean; web: boolean; plan: boolean; any: boolean } {
  const text = i.text.trim();
  if (!text || i.smallTalk) return { rewrite: false, web: false, plan: false, any: false };
  const rewrite = needsRewrite(text, i.history);
  const web = i.wantWeb && i.webLocal === null;
  // A long, rambling message is condensed into a search query by the model.
  const plan = i.wantWeb && !!i.webLocal?.search && text.length > 160;
  return { rewrite, web, plan, any: rewrite || web || plan };
}

const PROMPT = `You prepare one chat turn. Read the conversation and the latest user message and reply with only JSON:
{"standalone":"...","needsWeb":true,"freshness":"recent","queries":["..."],"needsKb":true,"pastRef":false}
- standalone: the latest message as one self-contained question in the user's language, pronouns and references resolved from the conversation; unchanged if it already stands alone.
- needsWeb: true when the answer depends on recent or changing information (news, prices, versions, releases, who holds a role), specific facts about named products, companies, people, places, papers or events, statistics, or when the user wants sources. false for coding help, debugging, established concepts, math, writing, opinions, the user's own data or files, greetings, or follow-ups the chat already answers.
- freshness: "breaking" (news of the last days), "recent" (facts that change over months: versions, prices, releases) or "evergreen".
- queries: exactly 1 keyword search query of 3-10 words; 2 only when comparing several things. No quotes or operators. Keep names, numbers and identifiers exactly.
- needsKb: false only for greetings, thanks, pure math or pure writing tasks; otherwise true.
- pastRef: true only if the user refers to an earlier conversation ("last time", "we discussed", "my chat about").`;

const bool = (v: unknown): boolean | null => (v === true || v === "true" ? true : v === false || v === "false" ? false : null);

/** Parses the model's reply; null when it holds no usable JSON. Tolerates fences, chatter and wrong types. */
export function parsePreflight(raw: string, text: string): Omit<Preflight, "via"> | null {
  let j: Record<string, unknown>;
  try {
    const v = extractJson(raw.replace(/<think>[\s\S]*?<\/think>/gi, ""), "{");
    if (!v || typeof v !== "object" || Array.isArray(v)) return null;
    j = v as Record<string, unknown>;
  } catch {
    return null;
  }
  const known = ["standalone", "needsWeb", "freshness", "queries", "needsKb", "pastRef"];
  if (!known.some((k) => k in j)) return null;
  const standalone = typeof j.standalone === "string" && j.standalone.trim().length >= 3 ? j.standalone.trim().slice(0, 500) : text.trim();
  const seen = new Set<string>();
  const queries = (Array.isArray(j.queries) ? j.queries : [])
    .filter((q): q is string => typeof q === "string")
    .map((q) => q.replace(/\s+/g, " ").trim().slice(0, 200))
    .filter((q) => q.length >= 3 && !seen.has(q.toLowerCase()) && !!seen.add(q.toLowerCase()))
    .slice(0, MAX_QUERIES);
  const freshness = j.freshness === "breaking" || j.freshness === "recent" || j.freshness === "evergreen" ? j.freshness : null;
  return { standalone, needsWeb: bool(j.needsWeb), freshness, queries, needsKb: bool(j.needsKb), pastRef: bool(j.pastRef) };
}

/** The no-model preflight: heuristic standalone and queries, the local web decision (or "no web" when unsure). */
export function heuristicPreflight(i: PreflightInput): Preflight {
  const text = i.text.trim();
  const standalone = heuristicStandalone(text, i.history, i.topics) || text;
  const queries = heuristicQueries(text, { standalone: standalone !== text ? standalone : undefined, topics: i.topics, previousUser: [...i.history].reverse().find((m) => m.role === "user")?.content }).slice(0, MAX_QUERIES);
  return {
    standalone,
    needsWeb: i.webLocal ? i.webLocal.search : i.wantWeb ? false : null,
    freshness: classifyFreshness(standalone),
    queries,
    needsKb: null,
    pastRef: null,
    via: "heuristic",
  };
}

// ---- how the chat route uses the preflight (kept pure so scripts and tests can drive it) ----------------------

const NO_SEARCH: SearchDecision = { search: false, query: "", reason: "none" };

/**
 * The turn's web decision: the local rules first (also on the resolved standalone question), then the preflight's
 * verdict. When neither can say (no preflight, or it failed) the answer is "no search".
 */
export function decideWeb(o: { wantWeb: boolean; webLocal: SearchDecision | null; standalone: string; rewrittenByModel: boolean; pre: Preflight | null; decideLocal: (q: string) => SearchDecision | null }): SearchDecision {
  if (!o.wantWeb) return NO_SEARCH;
  const local = o.webLocal ?? (o.rewrittenByModel ? o.decideLocal(o.standalone) : null);
  if (local) return local;
  const { pre } = o;
  if (pre?.via === "model" && pre.needsWeb !== null) {
    return { search: pre.needsWeb, query: pre.queries[0] ?? o.standalone.slice(0, 200), reason: pre.needsWeb ? "model" : "none" };
  }
  return NO_SEARCH;
}

/**
 * Query texts whose embeddings the knowledge base, past-chat recall and memory recall will need this turn. They are
 * requested together up front, so the turn makes one embedding request however many tools embed. Empty when none will.
 */
export function embedTextsForTurn(o: { hasMemory: boolean; knowledge: boolean; ragRewrite: boolean; smallTalk: boolean; aboutAttachments: boolean; lastUser: string; standalone: string; queries: string[]; /** The text past-chat recall will embed, when it will run. */ recallText?: string }): string[] {
  if (!(o.hasMemory || o.knowledge) || o.smallTalk || o.aboutAttachments) return [];
  const raw = o.lastUser.trim().slice(0, 500);
  return [o.standalone.slice(0, 500), ...(o.knowledge && o.ragRewrite && raw ? [raw, ...o.queries] : []), ...(o.recallText ? [o.recallText] : [])].filter((t, i, a) => t && a.indexOf(t) === i);
}

const cache = new Map<string, Preflight>();

/**
 * The preflight for a turn. One model call at most (first small model that
 * answers within the deadline); a heuristic result when none does. Never throws.
 */
export async function runPreflight(i: PreflightInput, opts: { timeoutMs?: number; ask?: AskSmallFn; models?: string[] } = {}): Promise<Preflight> {
  const text = i.text.trim();
  const recent = i.history.slice(-4);
  const key = `${recent.slice(-3).map((m) => m.content.slice(0, 100)).join("|")}#${text}#${i.wantWeb}`.toLowerCase();
  const hit = cache.get(key);
  if (hit) return hit;
  const ask = opts.ask ?? askSmall;
  const convo = recent.map((m) => `${m.role === "user" ? "User" : "Assistant"}: ${m.content.replace(/\s+/g, " ").slice(0, 350)}`).join("\n");
  const messages: Message[] = [
    { role: "system", content: PROMPT },
    { role: "user", content: `${convo ? `Conversation:\n${convo}\n\n` : ""}Latest user message: ${text.slice(0, 600)}` },
  ];
  const deadline = Date.now() + (opts.timeoutMs ?? PREFLIGHT_MS);
  for (const model of opts.models ?? SMALL_MODELS) {
    const left = deadline - Date.now();
    if (left < 400) break;
    try {
      const raw = await ask(model, messages, "preflight", left, { maxTokens: 400, reasoningEffort: "low" });
      const parsed = parsePreflight(raw, text);
      if (!parsed) throw new Error("unusable preflight reply");
      const out: Preflight = { ...parsed, via: "model" };
      cache.set(key, out);
      if (cache.size > 300) cache.delete(cache.keys().next().value as string);
      return out;
    } catch (e) {
      log.warn("preflight failed", { model, message: (e as Error).message?.slice(0, 100) });
    }
  }
  return heuristicPreflight(i);
}
