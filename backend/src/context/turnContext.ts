// The conversation context of one chat turn, built once and handed to every
// tool (web search, knowledge base, GitHub, images, follow-ups, round table,
// docs, cross-chat recall) so each plans with what the chat is actually about
// instead of guessing from the last message.
//
// Everything here is local and cheap except the standalone-question rewrite,
// which runs at most once per turn under a short deadline and falls back to a
// heuristic.
import { analyze, type Analysis } from "../nlp/index.js";
import { classifyIntent, type IntentLabel } from "../nlp/intent.js";
import { extractEntities, type Entity } from "../nlp/entities.js";
import { heuristicStandalone, needsRewrite, rewriteTurn, type HistoryMsg, type Rewrite } from "../retrieval/rewrite.js";
import { repoRefs } from "../github/grounding.js";
import { detectPastReference, type PastReference } from "../recall/detect.js";
import { topicOf } from "../web/images.js";

export type TurnMessage = { role: "user" | "assistant"; content: string; attachments?: string[] };
export type AttachmentInfo = { id: string; name: string; kind: string };
export type Topics = {
  /** "owner/repo", most recent first. */
  repos: string[];
  /** File names and paths discussed or attached. */
  files: string[];
  /** Generated doc ids linked in the chat. */
  docs: string[];
  /** Products, people, orgs, identifiers... ranked by how recent and how often. */
  entities: string[];
};

export type ToolName = "web" | "rag" | "github" | "images" | "followups" | "table" | "doc" | "recall";

/** Context budget per tool, in tokens (about 4 characters each). */
export const TOOL_BUDGET_TOKENS: Record<ToolName, number> = {
  web: 300,
  rag: 250,
  github: 150,
  images: 80,
  followups: 400,
  table: 900,
  doc: 800,
  recall: 200,
};
/** Budget of the verbatim recent turns kept in the context itself. */
export const TURNS_BUDGET_TOKENS = 1600;
export const MAX_TURNS = 8;
export const TURN_CHARS = 600;
const SCAN_MESSAGES = 12;
const REWRITE_MS = 2_000;

const CHARS_PER_TOKEN = 4;
const clip = (s: string, n: number) => (s.length > n ? `${s.slice(0, Math.max(n - 1, 0))}…` : s);
const flat = (s: string) => s.replace(/\s+/g, " ").trim();

export type TurnContext = {
  /** The last turns, newest last, trimmed to [TURNS_BUDGET_TOKENS]. The latest user message is not included. */
  turns: TurnMessage[];
  summary: string | null;
  /** The latest message as one self-contained question. */
  standalone: string;
  /** Extra phrasings of it (0-3), only when a model rewrote it. */
  queries: string[];
  rewrittenBy: "none" | "model" | "heuristic";
  /** NLP of the latest message. */
  nlp: Analysis;
  /** Entities of the latest message first, then those of recent messages. */
  entities: Entity[];
  /** Intent labels of the latest message first, then of the recent user messages. */
  recentIntents: IntentLabel[];
  topics: Topics;
  attachments: AttachmentInfo[];
  /** The "what you know about the user" block, when memory is on. */
  memory: string | null;
  pastRef: PastReference;
  lastUser: string;
};

// ---- trimming ------------------------------------------------------------------------

/** The newest messages that fit [budgetTokens], oldest first; each message is cut to [perMessageChars]. */
export function trimTurns<T extends { role: string; content: string }>(messages: T[], budgetTokens = TURNS_BUDGET_TOKENS, perMessageChars = TURN_CHARS, maxTurns = MAX_TURNS): T[] {
  const out: T[] = [];
  let left = budgetTokens * CHARS_PER_TOKEN;
  for (let i = messages.length - 1; i >= 0 && out.length < maxTurns; i--) {
    let content = clip(flat(messages[i].content), perMessageChars);
    if (!content) continue;
    if (content.length > left) {
      if (out.length > 0) break;
      content = clip(content, Math.max(left, 0)); // the newest turn is always kept, cut to fit
    }
    left -= content.length;
    out.unshift({ ...messages[i], content });
  }
  return out;
}

// ---- topics --------------------------------------------------------------------------

const DOC_LINK = /\bdoc:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/gi;
const FILE_NAME = /(?<![\w/.-])[\w.-]+\.(?:dart|ts|tsx|js|jsx|py|go|rs|java|kt|swift|md|json|ya?ml|toml|sql|prisma|css|html|pdf|docx?|xlsx?|csv|txt)\b/gi;
/** Entity types worth carrying across turns as "what we are talking about". */
const TOPIC_TYPES = new Set(["tech", "org", "person", "name", "identifier", "repo"]);

type Scored = Map<string, { text: string; score: number }>;
const bump = (m: Scored, text: string, w: number) => {
  const key = text.toLowerCase();
  const cur = m.get(key);
  if (cur) cur.score += w;
  else m.set(key, { text, score: w });
};
const top = (m: Scored, n: number) => [...m.values()].sort((a, b) => b.score - a.score).slice(0, n).map((v) => v.text);

/**
 * What the recent messages are about: repos, files, docs and named things, each
 * ranked by recency (newest weighs most) and repetition. [names] maps an
 * attachment id to its file name.
 */
export function extractTopics(messages: TurnMessage[], names: Map<string, AttachmentInfo> = new Map(), now = new Date()): Topics {
  const repos: Scored = new Map();
  const files: Scored = new Map();
  const docs: Scored = new Map();
  const entities: Scored = new Map();
  const recent = messages.slice(-SCAN_MESSAGES);
  recent.forEach((m, i) => {
    const age = recent.length - 1 - i;
    const w = 1 / (1 + age * 0.6) + (m.role === "user" ? 0.3 : 0);
    const text = m.content.slice(0, 2500);
    for (const r of repoRefs(text)) bump(repos, `${r.owner}/${r.repo}`, w);
    for (const f of text.match(FILE_NAME) ?? []) bump(files, f, w);
    for (const d of text.matchAll(DOC_LINK)) bump(docs, d[1].toLowerCase(), w);
    for (const id of m.attachments ?? []) {
      const a = names.get(id);
      if (a?.name) bump(files, a.name, w + 0.5);
    }
    for (const e of extractEntities(text, now)) {
      if (!TOPIC_TYPES.has(e.type)) continue;
      if (e.type === "repo") bump(repos, e.value, w);
      else bump(entities, e.value, w * (e.type === "tech" ? 0.8 : 1));
    }
  });
  return { repos: top(repos, 5), files: top(files, 6), docs: top(docs, 4), entities: top(entities, 8) };
}

// ---- builder -------------------------------------------------------------------------

export type BuildInput = {
  /** The messages sent for this turn, ending with the latest user message. */
  messages: TurnMessage[];
  /** The rolling summary of the turns that were cut off, if any. */
  summary?: string | null;
  /** The latest user text with attachment placeholders removed. */
  lastUserText: string;
  nlp: Analysis;
  attachments?: AttachmentInfo[];
  memory?: string | null;
  /** Whether any tool needs the standalone question (web, knowledge base, recall). */
  wantStandalone?: boolean;
};

export type BuildDeps = { rewrite?: (query: string, history: HistoryMsg[], opts: { topics: string[]; timeoutMs: number }) => Promise<Rewrite> };

/** Builds the context for one turn. Never throws; the rewrite is time-boxed with a heuristic fallback. */
export async function buildTurnContext(input: BuildInput, deps: BuildDeps = {}): Promise<TurnContext> {
  const all = input.messages;
  const lastIdx = all.map((m) => m.role).lastIndexOf("user");
  const before = lastIdx >= 0 ? all.slice(0, lastIdx) : all;
  const names = new Map((input.attachments ?? []).map((a) => [a.id, a]));
  const topics = extractTopics(all, names);

  // Entities and intents accumulate over the recent user messages, newest first.
  const entities: Entity[] = [...input.nlp.entities];
  const recentIntents: IntentLabel[] = [input.nlp.intent.top];
  const seen = new Set(entities.map((e) => `${e.type}:${e.value.toLowerCase()}`));
  for (const m of [...before].reverse().filter((x) => x.role === "user").slice(0, 3)) {
    for (const e of extractEntities(m.content.slice(0, 1500))) {
      const k = `${e.type}:${e.value.toLowerCase()}`;
      if (!seen.has(k)) {
        seen.add(k);
        entities.push(e);
      }
    }
    const label = classifyIntent(m.content.slice(0, 600)).top;
    if (!recentIntents.includes(label)) recentIntents.push(label);
  }

  const history: HistoryMsg[] = before.map((m) => ({ role: m.role, content: m.content }));
  const text = input.lastUserText.trim();
  let standalone = text;
  let queries: string[] = [];
  let rewrittenBy: TurnContext["rewrittenBy"] = "none";
  if (input.wantStandalone !== false && text && needsRewrite(text, history)) {
    const run = deps.rewrite ?? ((q, h, o) => rewriteTurn(q, h, o));
    const hint = [...topics.repos, ...topics.entities];
    try {
      const r = await run(text, history, { topics: hint, timeoutMs: REWRITE_MS });
      standalone = r.standalone || text;
      queries = r.queries;
      // The rewrite returns the heuristic form on failure, which has no variants.
      rewrittenBy = r.via;
    } catch {
      standalone = heuristicStandalone(text, history, hint);
      rewrittenBy = "heuristic";
    }
  }

  return {
    turns: trimTurns(before),
    summary: input.summary?.trim() || null,
    standalone,
    queries,
    rewrittenBy,
    nlp: input.nlp,
    entities,
    recentIntents,
    topics,
    attachments: input.attachments ?? [],
    memory: input.memory ?? null,
    pastRef: detectPastReference(text),
    lastUser: text,
  };
}

/** Convenience for callers that only have raw text (tests, scripts): analysis is done here. */
export async function buildTurnContextFromText(messages: TurnMessage[], opts: Partial<BuildInput> = {}, deps?: BuildDeps): Promise<TurnContext> {
  const last = [...messages].reverse().find((m) => m.role === "user")?.content ?? "";
  const nlp = opts.nlp ?? analyze(last);
  return buildTurnContext({ messages, lastUserText: last, nlp, ...opts }, deps);
}

// ---- per-tool views ------------------------------------------------------------------

/** Names to steer a search toward, most relevant first (repos, then named things), within [tool]'s budget. */
export function topicTerms(ctx: TurnContext, tool: ToolName = "web"): string[] {
  const out: string[] = [];
  let left = TOOL_BUDGET_TOKENS[tool] * CHARS_PER_TOKEN;
  for (const t of [...ctx.topics.repos.slice(0, 2), ...ctx.topics.entities]) {
    if (t.length + 2 > left) break;
    out.push(t);
    left -= t.length + 2;
  }
  return out;
}

/** The context as short text for a tool's prompt: summary, topics, then the newest turns, within the tool's token budget. Empty when there is none. */
export function renderContext(ctx: Pick<TurnContext, "summary" | "topics" | "turns">, tool: ToolName, opts: { turns?: number } = {}): string {
  let left = TOOL_BUDGET_TOKENS[tool] * CHARS_PER_TOKEN;
  const parts: string[] = [];
  const add = (label: string, body: string, share = 1) => {
    if (!body || left < 80) return;
    const line = `${label}: ${clip(body, Math.floor(left * share))}`;
    parts.push(line);
    left -= line.length + 1;
  };
  if (ctx.summary) add("Earlier in this chat", flat(ctx.summary), 0.5);
  const names = [...ctx.topics.repos, ...ctx.topics.files, ...ctx.topics.entities].slice(0, 10).join(", ");
  add("Topics so far", names, 0.2);
  const turns = trimTurns(ctx.turns, Math.max(Math.floor(left / CHARS_PER_TOKEN), 0), 400, opts.turns ?? MAX_TURNS);
  if (turns.length) add("Recent turns", turns.map((t) => `${t.role === "user" ? "User" : "Assistant"}: ${t.content}`).join(" | "));
  return parts.join("\n");
}

/**
 * Search words for the image strip. A bare follow-up ("show me pictures of it")
 * has no topic of its own: it borrows the chat's main subject.
 */
export function imageQuery(question: string, ctx: TurnContext | null): string {
  const own = topicOf(question);
  if (!ctx || own.split(/\s+/).filter((w) => w.length > 2).length >= 2) return question;
  const subject = ctx.topics.repos[0]?.split("/")[1] ?? ctx.topics.entities[0];
  return subject ? `${subject} ${question}` : question;
}
