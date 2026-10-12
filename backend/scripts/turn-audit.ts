/**
 * Counts the upstream calls one chat turn makes, before and after the efficiency work, for 10 representative prompts.
 *
 *   pnpm exec tsx scripts/turn-audit.ts          # table + totals
 *   pnpm exec tsx scripts/turn-audit.ts --json   # machine readable
 *
 * LLM, embedding, search and page fetches are stubbed: nothing leaves the process. "After" drives the real decision
 * code (NLP, local search rules, preflight parsing/needs, embedding coalescing, memory/follow-up gating, query
 * planning, free-first provider choice, page-fetch skipping). "Before" re-states the rules the route used previously
 * (standalone rewrite, search-decision call, plan call, per-turn memory extraction, three separate embeddings,
 * year-variant second query, 4 page fetches, follow-ups for anything over 40 characters).
 * Time to first token is MODELLED from the assumed latencies below, not measured.
 */
import "dotenv/config";
import { analyze } from "../src/nlp/index.js";
import { needsRewrite } from "../src/retrieval/rewrite.js";
import { decideSearchLocal } from "../src/web/searchDecision.js";
import { decideWeb, embedTextsForTurn, preflightNeeds, runPreflight, type AskSmallFn } from "../src/context/preflight.js";
import { detectPastReference } from "../src/recall/detect.js";
import { recallQueryText } from "../src/recall/search.js";
import { embedQueries, stubQueryEmbedder } from "../src/embeddings/index.js";
import { classifyFreshness, detectIntents, heuristicQueries, isComparison, planFromPreflight } from "../src/web/plan.js";
import { freeFirst } from "../src/web/pipeline.js";
import { snippetAnswers } from "../src/web/budget.js";
import { detectExplicit } from "../src/memory/logic.js";
import { extractionPlan } from "../src/memory/batcher.js";
import { worthFollowups } from "../src/assist/suggest.js";
import { buildSystemPrompt, promptNeeds } from "../src/prompts/system.js";
import { maxTokensFor } from "../src/llm/router.js";
import { dedupeSeatQueries } from "../src/table/research.js";

type Msg = { role: "user" | "assistant"; content: string };
type Model = { standalone?: string; needsWeb?: boolean; freshness?: "breaking" | "recent" | "evergreen"; queries?: string[]; needsKb?: boolean; pastRef?: boolean };
type Scenario = {
  name: string;
  text: string;
  history: Msg[];
  web: boolean;
  kb: boolean;
  memory: boolean;
  table?: boolean;
  /** Length of the assistant's reply, in characters. */
  reply: number;
  /** What the small model would answer to the preflight / legacy deciders (stub). */
  model: Model;
  /** Of the 3 snippet-only search hits, how many already answer the question. */
  goodSnippets?: number;
  /** Whether the free no-quota sources return enough on their own (stub). */
  freeEnough?: boolean;
};

const A = (content: string): Msg => ({ role: "assistant", content });
const U = (content: string): Msg => ({ role: "user", content });

const SCENARIOS: Scenario[] = [
  { name: "greeting", text: "hi there!", history: [], web: true, kb: true, memory: true, reply: 60, model: {} },
  { name: "thanks", text: "thanks, that helped a lot", history: [U("how do I reverse a list in python"), A("Use reversed() or slicing, e.g. xs[::-1].")], web: true, kb: true, memory: true, reply: 45, model: {} },
  { name: "code question", text: "write a python function that removes duplicates from a list but keeps the order", history: [], web: true, kb: true, memory: true, reply: 900, model: {} },
  { name: "fresh fact", text: "what is the latest LTS version of Node.js?", history: [], web: true, kb: true, memory: true, reply: 350, model: { needsWeb: true, queries: ["Node.js latest LTS version"], freshness: "recent" }, goodSnippets: 1 },
  {
    name: "follow-up",
    text: "and what about Deno?",
    history: [U("what is the latest LTS version of Node.js?"), A("Node.js 24 is the current LTS line, released October 2025 with support until April 2028.")],
    web: true,
    kb: true,
    memory: true,
    reply: 320,
    model: { standalone: "What is the latest stable version of Deno?", needsWeb: true, queries: ["Deno latest stable version"], freshness: "recent" },
  },
  { name: "explain concept", text: "explain how HNSW indexes work in vector databases", history: [], web: true, kb: true, memory: true, reply: 1400, model: { needsWeb: false, queries: ["HNSW index vector database"], freshness: "evergreen" }, freeEnough: true },
  { name: "comparison", text: "React vs Vue for a large enterprise app", history: [], web: true, kb: true, memory: true, reply: 1500, model: { needsWeb: true, queries: ["React vs Vue enterprise app", "React Vue large scale 2026"], freshness: "recent" } },
  { name: "personal statement", text: "I'm a backend engineer at Acme and we mostly use Postgres and Flutter", history: [U("hello"), A("Hi! How can I help?")], web: true, kb: true, memory: true, reply: 220, model: { needsWeb: false } },
  { name: "past chat", text: "what did we discuss last time about Redis caching?", history: [U("hello"), A("Hi!")], web: true, kb: true, memory: true, reply: 600, model: { needsWeb: false, pastRef: true } },
  { name: "round table", text: "should we use Kafka or RabbitMQ for our order events? compare them", history: [], web: true, kb: true, memory: true, table: true, reply: 1800, model: { needsWeb: true, queries: ["Kafka vs RabbitMQ order events", "Kafka RabbitMQ throughput 2026"], freshness: "recent" } },
];

// Assumed latencies (ms) for the modelled time to first token.
const LAT = { llm: 700, embed: 350, db: 100, search: 1100, freeSearch: 500, fetch: 900, firstToken: 600 };
// Typical tokens (prompt + completion) of each auxiliary LLM call, from the prompts in the code.
const TOK = { preflight: 520, rewrite: 400, decide: 300, plan: 450, memory: 800, followups: 950, tableplan: 400 };

type Count = { llm: number; tokens: number; embed: number; search: number; fetch: number; ttft: number; notes: string[] };
const zero = (): Count => ({ llm: 0, tokens: 0, embed: 0, search: 0, fetch: 0, ttft: 0, notes: [] });
const aux = (c: Count) => c.llm + c.embed + c.search + c.fetch;

// Which free secondary sources each intent asks (Hacker News no longer answers plain code questions).
const SECONDARY_BEFORE: Record<string, string[]> = { encyclopedic: ["wikipedia"], academic: ["wikipedia", "arxiv"], news: ["hackernews"], code: ["hackernews", "stackexchange"], discussion: ["hackernews", "reddit"], repo: ["hackernews", "github"] };
const SECONDARY_AFTER: Record<string, string[]> = { ...SECONDARY_BEFORE, code: ["stackexchange"] };
const secondariesFor = (intents: string[], map = SECONDARY_BEFORE) => new Set(intents.flatMap((i) => map[i] ?? []));

// ---- before ---------------------------------------------------------------------------------------------------------

const legacyQueryCount = (q: string) => 1 + (classifyFreshness(q) !== "evergreen" && !/\b20\d\d\b/.test(q) && q.split(/\s+/).length <= 10 ? 1 : 0);
const FOLLOW_UP = /^(?:and|but|also|what about|how about|then|so|why|how|what|where|when|who|which|is|are|does|do|did|can|could)\b[^.?!]{0,60}\b(it|its|that|this|they|them|those|these|he|she|there|one|the same)\b|^(?:and|also|what about|how about|more|why|and then)\b/i;

function before(s: Scenario): Count {
  const c = zero();
  const nlp = analyze(s.text, s.history.filter((m) => m.role === "user").map((m) => m.content).reverse());
  const smallTalk = nlp.intent.top === "chitchat" && !nlp.intent.uncertain && nlp.intent.confidence >= 0.6;
  let pre = 0;
  if (needsRewrite(s.text, s.history)) (c.llm++, (c.tokens += TOK.rewrite), (pre += LAT.llm));
  let searching = false;
  let focusedByModel = false;
  if (s.web) {
    const local = decideSearchLocal(s.text, nlp.intent);
    if (local) searching = local.search;
    else {
      c.llm++;
      c.tokens += TOK.decide;
      pre += LAT.llm;
      searching = s.model.needsWeb === true;
      focusedByModel = searching;
    }
  }
  let webMs = 0;
  if (searching) {
    const q = (focusedByModel ? s.model.queries?.[0] : undefined) ?? s.text;
    const words = q.split(/\s+/).length;
    const prevUser = [...s.history].reverse().find((m) => m.role === "user");
    const needsPlan = !focusedByModel && ((q.length > 160) || (!!prevUser && (words < 4 || (words < 9 && FOLLOW_UP.test(q)))));
    if (needsPlan) (c.llm++, (c.tokens += TOK.plan), (webMs += LAT.llm));
    const nq = legacyQueryCount(q);
    const intents = detectIntents(q);
    c.search += nq + secondariesFor(intents).size;
    c.fetch += Math.min(4, 3);
    webMs += LAT.search + LAT.fetch;
    if (s.table) {
      c.llm++; // seat planner
      c.tokens += TOK.tableplan;
      c.search += 3 * (1 + secondariesFor(intents).size);
      c.fetch += 3 * 2;
      webMs += LAT.llm + LAT.search;
    }
  }
  // Embeddings: memory recall (raw text), knowledge base and past-chat recall each embedded on their own.
  const explicitPast = detectPastReference(s.text).explicit;
  if (s.memory) c.embed++;
  if (s.kb) c.embed++;
  if (explicitPast || (!smallTalk && s.text.length >= 12)) c.embed++;
  // Memory extraction on every turn that is not obviously small talk or tiny.
  if (s.memory && (detectExplicit(s.text) || s.text.length >= 12) && !smallTalk) (c.llm++, (c.tokens += TOK.memory));
  // Follow-up chips for any reply of 40+ characters.
  if (s.reply >= 40) (c.llm++, (c.tokens += TOK.followups));
  const kbMs = s.kb ? LAT.embed + LAT.db : 0;
  c.ttft = pre + Math.max(webMs, kbMs, explicitPast || !smallTalk ? LAT.embed + LAT.db : 0) + LAT.firstToken;
  return c;
}

// ---- after ----------------------------------------------------------------------------------------------------------

async function after(s: Scenario): Promise<Count> {
  const c = zero();
  const nlp = analyze(s.text, s.history.filter((m) => m.role === "user").map((m) => m.content).reverse());
  const smallTalk = nlp.intent.top === "chitchat" && !nlp.intent.uncertain && nlp.intent.confidence >= 0.6;
  const wantWeb = s.web;
  const webLocal = wantWeb ? decideSearchLocal(s.text, nlp.intent) : { search: false, query: "", reason: "none" as const };
  const needs = preflightNeeds({ text: s.text, history: s.history, wantWeb, webLocal, smallTalk });
  let pre = null as Awaited<ReturnType<typeof runPreflight>> | null;
  let preMs = 0;
  if (needs.any) {
    const ask: AskSmallFn = async () => {
      c.llm++;
      c.tokens += TOK.preflight;
      return JSON.stringify({ standalone: s.model.standalone ?? s.text, needsWeb: s.model.needsWeb ?? false, freshness: s.model.freshness ?? "evergreen", queries: s.model.queries ?? [s.text], needsKb: s.model.needsKb ?? true, pastRef: s.model.pastRef ?? false });
    };
    pre = await runPreflight({ text: `${s.text} #${s.name}`, history: s.history, wantWeb, webLocal }, { ask });
    preMs = LAT.llm;
  }
  const standalone = pre?.standalone.replace(` #${s.name}`, "") ?? s.text;
  const decision = decideWeb({ wantWeb, webLocal, standalone, rewrittenByModel: pre?.via === "model" && needsRewrite(s.text, s.history), pre, decideLocal: (q) => decideSearchLocal(q, nlp.intent) });
  let webMs = 0;
  if (decision.search) {
    const plan = pre?.via === "model" && pre.queries.length ? planFromPreflight(s.text, pre.queries, pre.freshness) : { queries: heuristicQueries(decision.query || s.text), fresh: classifyFreshness(s.text), intents: detectIntents(s.text), via: "heuristic" as const };
    const free = freeFirst(plan);
    const sec = secondariesFor(plan.intents, SECONDARY_AFTER);
    const skipOllama = free && sec.size > 0 && s.freeEnough === true;
    c.search += (skipOllama ? 0 : plan.queries.length) + sec.size;
    const body = (good: boolean) => ({ snippet: good ? `${plan.queries[0]} ${"details ".repeat(60)}` : "unrelated page", text: undefined as string | undefined });
    const snippetOnly = [0, 1, 2].map((i) => body(i < (s.goodSnippets ?? 0)));
    const need = snippetOnly.filter((x) => !snippetAnswers(x, plan.queries.join(" ")));
    c.fetch += Math.min(3, need.length);
    webMs += (skipOllama ? LAT.freeSearch : LAT.search) + (need.length ? LAT.fetch : 0);
    if (s.table) {
      // Seats: the preflight already wrote two angles for a comparison (no planner call); identical seat queries are searched once.
      const seats = dedupeSeatQueries([...(pre?.queries ?? []), `${plan.queries[0]} official source`, `${plan.queries[0]} analysis`]).unique.slice(0, 3);
      if (!(pre && pre.queries.length >= 3)) {
        const seeded = dedupeSeatQueries([plan.queries[0], ...(pre?.queries ?? [])]).unique.length - 1;
        if (seeded < 2) (c.llm++, (c.tokens += TOK.tableplan), (webMs += LAT.llm));
      }
      c.search += seats.length * (1 + sec.size);
      c.fetch += seats.length * 1;
      webMs += LAT.search;
    }
  }
  // Embeddings: one coalesced request for everything the tools need.
  let requests = 0;
  const restore = stubQueryEmbedder(async (texts) => (requests++, texts.map((t) => [t.length])));
  try {
    const past = detectPastReference(s.text);
    const recallText = past.explicit || (!smallTalk && standalone.length >= 12) ? recallQueryText({ query: standalone, topic: past.topic, explicit: past.explicit }) : undefined;
    const texts = embedTextsForTurn({ hasMemory: s.memory, knowledge: s.kb, ragRewrite: true, smallTalk, aboutAttachments: false, lastUser: s.text, standalone, queries: pre?.via === "model" ? pre.queries : [], recallText });
    if (texts.length) await embedQueries(texts);
    else if (recallText) await embedQueries([recallText]); // a lone consumer (recall) embeds for itself
  } finally {
    restore();
  }
  c.embed += requests;
  // Memory: explicit asks at once, personal statements batched (1 call per 3 such turns), everything else skipped.
  const plan = extractionPlan(s.text, !!detectExplicit(s.text), nlp.intent);
  if (s.memory && plan === "now") (c.llm++, (c.tokens += TOK.memory));
  if (s.memory && plan === "batch") (c.llm += 1 / 3, (c.tokens += TOK.memory / 3));
  if (worthFollowups("x".repeat(s.reply), nlp.intent)) (c.llm++, (c.tokens += TOK.followups));
  const kbMs = s.kb && !smallTalk ? LAT.embed + LAT.db : 0;
  c.ttft = preMs + Math.max(webMs, kbMs, !smallTalk ? LAT.embed + LAT.db : 0) + LAT.firstToken;
  return c;
}

// ---- system prompt size per intent ---------------------------------------------------------------------------------

function promptSizes() {
  const rows: Array<{ intent: string; chars: number; tokens: number }> = [];
  const full = buildSystemPrompt("default", undefined, new Date("2026-10-12")).length;
  rows.push({ intent: "(full, no trimming)", chars: full, tokens: Math.ceil(full / 4) });
  for (const [label, text] of [["small talk", "hi there!"], ["code question", "write a python function that removes duplicates"], ["explain", "explain how HNSW indexes work"], ["ui / html", "build me a landing page dashboard in html"], ["github", "show me the facebook/react repo commits on github"]] as const) {
    const n = promptNeeds(text, false, analyze(text).intent);
    const chars = buildSystemPrompt("default", undefined, new Date("2026-10-12"), n).length;
    rows.push({ intent: label, chars, tokens: Math.ceil(chars / 4) });
  }
  return rows;
}

// ---- run ------------------------------------------------------------------------------------------------------------

const pct = (a: number, b: number) => (a === 0 ? 0 : Math.round(((a - b) / a) * 100));
const f1 = (n: number) => (Math.round(n * 10) / 10).toString();

const rows: Array<{ name: string; before: Count; after: Count; maxTokens: number }> = [];
for (const s of SCENARIOS) {
  const nlp = analyze(s.text, s.history.filter((m) => m.role === "user").map((m) => m.content).reverse());
  rows.push({ name: s.name, before: before(s), after: await after(s), maxTokens: maxTokensFor({ mode: "default", intent: nlp.intent }) });
}
const sum = (k: "before" | "after", f: (c: Count) => number) => rows.reduce((n, r) => n + f(r[k]), 0);
const totals = {
  auxBefore: sum("before", aux),
  auxAfter: sum("after", aux),
  llmBefore: sum("before", (c) => c.llm),
  llmAfter: sum("after", (c) => c.llm),
  embedBefore: sum("before", (c) => c.embed),
  embedAfter: sum("after", (c) => c.embed),
  searchBefore: sum("before", (c) => c.search),
  searchAfter: sum("after", (c) => c.search),
  fetchBefore: sum("before", (c) => c.fetch),
  fetchAfter: sum("after", (c) => c.fetch),
  tokBefore: sum("before", (c) => c.tokens),
  tokAfter: sum("after", (c) => c.tokens),
  ttftBefore: sum("before", (c) => c.ttft) / rows.length,
  ttftAfter: sum("after", (c) => c.ttft) / rows.length,
};

if (process.argv.includes("--json")) {
  console.log(JSON.stringify({ rows, totals, promptSizes: promptSizes() }, null, 2));
} else {
  const pad = (s: string, n: number) => s.padEnd(n);
  console.log(`${pad("prompt", 20)} ${pad("llm b/a", 10)} ${pad("embed b/a", 10)} ${pad("search b/a", 11)} ${pad("fetch b/a", 10)} ${pad("aux b/a", 9)} ${pad("aux tok b/a", 13)} ttft ms b/a (modelled)`);
  for (const r of rows) {
    console.log(
      `${pad(r.name, 20)} ${pad(`${f1(r.before.llm)}/${f1(r.after.llm)}`, 10)} ${pad(`${r.before.embed}/${r.after.embed}`, 10)} ${pad(`${r.before.search}/${r.after.search}`, 11)} ${pad(`${r.before.fetch}/${r.after.fetch}`, 10)} ${pad(`${f1(aux(r.before))}/${f1(aux(r.after))}`, 9)} ${pad(`${Math.round(r.before.tokens)}/${Math.round(r.after.tokens)}`, 13)} ${r.before.ttft}/${r.after.ttft}`,
    );
  }
  console.log("-".repeat(110));
  console.log(
    `${pad("TOTAL (10 turns)", 20)} ${pad(`${f1(totals.llmBefore)}/${f1(totals.llmAfter)}`, 10)} ${pad(`${totals.embedBefore}/${totals.embedAfter}`, 10)} ${pad(`${totals.searchBefore}/${totals.searchAfter}`, 11)} ${pad(`${totals.fetchBefore}/${totals.fetchAfter}`, 10)} ${pad(`${f1(totals.auxBefore)}/${f1(totals.auxAfter)}`, 9)} ${pad(`${Math.round(totals.tokBefore)}/${Math.round(totals.tokAfter)}`, 13)} ${Math.round(totals.ttftBefore)}/${Math.round(totals.ttftAfter)} (mean)`,
  );
  console.log(`\nauxiliary calls (aux LLM + embed + search + fetch): ${f1(totals.auxBefore)} -> ${f1(totals.auxAfter)}  (${pct(totals.auxBefore, totals.auxAfter)}% fewer)`);
  console.log(`auxiliary LLM calls: ${f1(totals.llmBefore)} -> ${f1(totals.llmAfter)}  (${pct(totals.llmBefore, totals.llmAfter)}% fewer); aux LLM tokens ${Math.round(totals.tokBefore)} -> ${Math.round(totals.tokAfter)} (${pct(totals.tokBefore, totals.tokAfter)}% fewer)`);
  console.log(`mean modelled time to first token: ${Math.round(totals.ttftBefore)} ms -> ${Math.round(totals.ttftAfter)} ms (${pct(totals.ttftBefore, totals.ttftAfter)}% lower)`);
  console.log("\nsystem prompt size (default mode, no profile):");
  for (const p of promptSizes()) console.log(`  ${pad(p.intent, 22)} ${p.chars} chars (~${p.tokens} tokens)`);
  console.log("\nreply cap (max_tokens): " + rows.map((r) => `${r.name}=${r.maxTokens}`).join(", "));
}
