import { test } from "node:test";
import assert from "node:assert/strict";
import { decideWeb, embedTextsForTurn, heuristicPreflight, parsePreflight, preflightNeeds, runPreflight, type AskSmallFn, type Preflight } from "../src/context/preflight.js";
import { compactHistory } from "../src/memory/compact.js";
import { embedQueries, stubQueryEmbedder } from "../src/embeddings/index.js";
import { dedupeSeatQueries, runSeatResearch } from "../src/table/research.js";
import { searchCacheKey } from "../src/web/cacheStore.js";
import { decideSearchLocal } from "../src/web/searchDecision.js";
import { fitBudget, snippetAnswers } from "../src/web/budget.js";
import { heuristicQueries, isComparison, planFromPreflight } from "../src/web/plan.js";
import { extractionPlan, TurnBatcher } from "../src/memory/batcher.js";
import { analyzeMemory } from "../src/nlp/memoryIntent.js";
import { worthFollowups } from "../src/assist/suggest.js";
import { maxTokensFor, preferSmall } from "../src/llm/router.js";
import { newTurnCounters, tally } from "../src/db/usage.js";

const intent = (top: string, confidence = 0.9, uncertain = false) => ({ top, confidence, uncertain });

// ---- preflight JSON ------------------------------------------------------------

test("parsePreflight reads the full JSON, tolerating fences and chatter", () => {
  const raw = 'Sure!\n```json\n{"standalone":"What is the price of the Pixel 10 in India?","needsWeb":true,"freshness":"recent","queries":["Pixel 10 price India","Pixel 10 price India","pixel 10 launch"],"needsKb":false,"pastRef":"false"}\n```';
  const p = parsePreflight(raw, "and in India?")!;
  assert.equal(p.standalone, "What is the price of the Pixel 10 in India?");
  assert.equal(p.needsWeb, true);
  assert.equal(p.freshness, "recent");
  assert.deepEqual(p.queries, ["Pixel 10 price India", "pixel 10 launch"]); // deduped, capped at 2
  assert.equal(p.needsKb, false);
  assert.equal(p.pastRef, false); // "false" string accepted
});

test("parsePreflight fills gaps and rejects junk", () => {
  const p = parsePreflight('{"needsWeb":"maybe","freshness":"someday","queries":[1,null,"ok"]}', "hello there")!;
  assert.equal(p.standalone, "hello there"); // missing standalone falls back to the message
  assert.equal(p.needsWeb, null);
  assert.equal(p.freshness, null);
  assert.deepEqual(p.queries, []); // "ok" is too short to be a query
  assert.equal(parsePreflight("no json at all", "x"), null);
  assert.equal(parsePreflight('{"unrelated": 1}', "x"), null);
  assert.equal(parsePreflight("[1,2]", "x"), null);
});

test("runPreflight: one call on success, heuristic fallback on bad JSON or errors", async () => {
  const history = [
    { role: "user", content: "Tell me about the Pixel 10" },
    { role: "assistant", content: "The Pixel 10 is Google's phone." },
  ];
  const input = { text: "what about its price?", history, wantWeb: true, webLocal: null };
  let calls = 0;
  const good: AskSmallFn = async () => (calls++, '{"standalone":"What is the price of the Pixel 10?","needsWeb":true,"freshness":"recent","queries":["Pixel 10 price"],"needsKb":true,"pastRef":false}');
  const ok = await runPreflight({ ...input, text: "what about its price? #good" }, { ask: good });
  assert.equal(ok.via, "model");
  assert.equal(calls, 1);
  assert.equal(ok.needsWeb, true);

  let bad = 0;
  const garbage: AskSmallFn = async () => (bad++, "I cannot do that");
  const fb = await runPreflight({ ...input, text: "what about its price? #garbage" }, { ask: garbage, models: ["m1", "m2"] });
  assert.equal(fb.via, "heuristic");
  assert.equal(bad, 2); // each model tried once, then the heuristic
  assert.match(fb.standalone, /Pixel 10/);
  assert.equal(fb.needsWeb, false); // unsure and the model is down: no search

  const boom: AskSmallFn = async () => {
    throw new Error("429");
  };
  const fb2 = await runPreflight({ ...input, text: "what about its price? #boom" }, { ask: boom, models: ["m1"] });
  assert.equal(fb2.via, "heuristic");
  assert.ok(fb2.queries.length >= 1);
});

test("preflightNeeds: confident standalone turns need no model call", () => {
  const none = { search: false, query: "", reason: "intent" as const };
  assert.equal(preflightNeeds({ text: "write a haiku about rain", history: [], wantWeb: true, webLocal: none }).any, false);
  assert.equal(preflightNeeds({ text: "thanks!", history: [], wantWeb: false, webLocal: none }).any, false);
  assert.equal(preflightNeeds({ text: "thanks!", history: [{ role: "assistant", content: "Done." }], wantWeb: true, webLocal: null, smallTalk: true }).any, false);
  // A follow-up needs the rewrite; an unsure web decision needs the model; a long searched message needs a query.
  const hist = [{ role: "assistant", content: "Some answer" }];
  assert.equal(preflightNeeds({ text: "and the second one?", history: hist, wantWeb: false, webLocal: none }).rewrite, true);
  assert.equal(preflightNeeds({ text: "tell me about the history of the Roman aqueducts in detail", history: [], wantWeb: true, webLocal: null }).web, true);
  const long = { search: true, query: "x", reason: "explicit" as const };
  assert.equal(preflightNeeds({ text: `search ${"word ".repeat(40)}`, history: [], wantWeb: true, webLocal: long }).plan, true);
  assert.equal(preflightNeeds({ text: "search latest node release", history: [], wantWeb: true, webLocal: long }).any, false);
});

test("heuristicPreflight carries the topic over for a follow-up", () => {
  const h = heuristicPreflight({ text: "and its price?", history: [{ role: "user", content: "Tell me about the Pixel 10" }, { role: "assistant", content: "ok" }], wantWeb: true, webLocal: null });
  assert.match(h.standalone, /Pixel 10/);
  assert.equal(h.via, "heuristic");
});

test("decideSearchLocal settles explicit, fresh and confident turns; null means ask a model", () => {
  assert.equal(decideSearchLocal("search for the best pizza in rome")?.reason, "explicit");
  assert.equal(decideSearchLocal("what is the latest version of node")?.search, true);
  assert.equal(decideSearchLocal("")?.search, false);
  assert.equal(decideSearchLocal("tell me about the architecture of the Hagia Sophia"), null);
});

// ---- shared embedding -----------------------------------------------------------

test("embedQueries: concurrent consumers of one turn share ONE request, later calls hit the cache", async () => {
  const seen: string[][] = [];
  const restore = stubQueryEmbedder(async (texts) => (seen.push([...texts]), texts.map((t) => [t.length, 1])));
  try {
    // knowledge base (raw + standalone), past-chat recall (standalone), memory recall (standalone), all at once.
    const [kb, recall, memory] = await Promise.all([
      embedQueries(["and the price?", "Pixel 10 price"]),
      embedQueries(["Pixel 10 price"]),
      new Promise<number[][]>((r) => setTimeout(() => embedQueries(["Pixel 10 price"]).then(r), 5)),
    ]);
    assert.equal(seen.length, 1, `expected one embedding request, got ${seen.length}`);
    assert.deepEqual(seen[0].sort(), ["Pixel 10 price", "and the price?"]);
    assert.deepEqual(kb[1], recall[0]);
    assert.deepEqual(recall[0], memory[0]);
    await embedQueries(["Pixel 10 price"]);
    assert.equal(seen.length, 1); // cached
  } finally {
    restore();
  }
});

test("embedQueries: a failed request rejects every waiter and is not cached", async () => {
  let n = 0;
  const restore = stubQueryEmbedder(async (texts) => {
    if (n++ === 0) throw new Error("down");
    return texts.map(() => [1]);
  });
  try {
    const results = await Promise.allSettled([embedQueries(["a"]), embedQueries(["a"])]);
    assert.ok(results.every((r) => r.status === "rejected"));
    assert.deepEqual(await embedQueries(["a"]), [[1]]);
  } finally {
    restore();
  }
});

// ---- round table dedupe ---------------------------------------------------------

test("dedupeSeatQueries maps equivalent queries to one search", () => {
  const { unique, seatToUnique } = dedupeSeatQueries(["Rust vs Go speed", "rust vs go  speed!", "Go memory model"]);
  assert.deepEqual(unique, ["Rust vs Go speed", "Go memory model"]);
  assert.deepEqual(seatToUnique, [0, 0, 1]);
});

test("runSeatResearch searches each distinct query once and fans the result out to the seats", async () => {
  const asked: string[] = [];
  const search = async (q: string) => (asked.push(q), [{ title: q, url: `https://x.test/${asked.length}`, content: `about ${q}` }]);
  const out = await runSeatResearch(["same thing", "Same thing.", "SAME   thing"], new AbortController().signal, search);
  assert.equal(asked.length, 1);
  assert.equal(out.length, 3);
  assert.ok(out.every((s) => s.results.length === 1 && s.results[0].url === "https://x.test/1"));
  assert.deepEqual(out.map((s) => s.seat), ["A", "B", "C"]);
  // A failing shared search leaves every seat that asked it without research.
  const failing = await runSeatResearch(["q one", "q one"], new AbortController().signal, async () => {
    throw new Error("rate limited");
  });
  assert.deepEqual(failing.map((s) => s.queries.length), [0, 0]);
});

// ---- search cache keying --------------------------------------------------------

test("searchCacheKey ignores case, punctuation and spacing, but not provider or freshness class", () => {
  const a = searchCacheKey("ollama", "recent", "  Node.js   LTS version? ");
  assert.equal(a, searchCacheKey("ollama", "recent", "node js lts version"));
  assert.notEqual(a, searchCacheKey("ollama", "evergreen", "node js lts version"));
  assert.notEqual(a, searchCacheKey("wikipedia", "recent", "node js lts version"));
  assert.notEqual(a, searchCacheKey("ollama", "recent", "node js lts versions"));
  assert.ok(searchCacheKey("p", "breaking", "x".repeat(2000)).length <= 400);
});

// ---- web: fewer queries, free first, budget -------------------------------------

test("one query by default, a second only for comparisons", () => {
  assert.equal(heuristicQueries("latest flutter release", {}, new Date("2026-10-01")).length, 1);
  assert.equal(heuristicQueries("react vs vue for large apps").length, 2);
  assert.equal(isComparison("difference between tcp and udp"), true);
  assert.equal(isComparison("what is tcp"), false);
  assert.equal(planFromPreflight("what is tcp", ["tcp protocol", "tcp handshake"], "evergreen").queries.length, 1);
  assert.equal(planFromPreflight("tcp vs udp", ["tcp vs udp", "tcp udp speed"], null).queries.length, 2);
});

test("snippetAnswers skips page fetches only when the text already covers the question", () => {
  const body = "Node.js 24 is the current LTS release line, released in October 2025, with long term support until April 2028. ".repeat(4);
  assert.equal(snippetAnswers({ snippet: body.slice(0, 400), text: body }, "node.js lts release"), true);
  assert.equal(snippetAnswers({ snippet: body.slice(0, 400), text: body }, "deno permissions model sandbox"), false);
  assert.equal(snippetAnswers({ snippet: "short", text: undefined }, "node lts"), false);
});

test("fitBudget cuts web evidence to the budget, best sources keep the most, small sources are untouched", () => {
  const para = (n: number) => `Paragraph ${n} about quantum error correction and surface codes, with threshold values near one percent for many hardware platforms today. `.repeat(6);
  const big = (n: number) => ({ id: `W${n}`, text: Array.from({ length: 12 }, (_, i) => para(i)).join("\n\n") });
  const items = [big(1), big(2), big(3), big(4), big(5)];
  const before = items.reduce((n, i) => n + i.text.length, 0);
  assert.ok(before > 10_000);
  const fitted = fitBudget(items, "surface code threshold", 6_000);
  const after = fitted.reduce((n, i) => n + i.text.length, 0);
  assert.ok(after <= 6_500, `after ${after}`);
  assert.ok(fitted[0].text.length >= fitted[4].text.length);
  const small = [{ id: "W1", text: "tiny" }];
  assert.equal(fitBudget(small, "x", 6_000), small);
});

// ---- memory batching ------------------------------------------------------------

test("extractionPlan: no LLM for chit-chat, questions or facts the rules read; batch other personal statements; unresolved explicit asks run at once", () => {
  const plan = (t: string) => extractionPlan(analyzeMemory(t));
  assert.equal(plan("thanks!"), "skip");
  assert.equal(plan("ok"), "skip");
  assert.equal(plan("How do I reverse a linked list in Python?"), "skip");
  // Rule-based slots (role, employer, tools): saved without any model call.
  assert.equal(plan("I'm a backend engineer at Acme and I use Postgres daily"), "skip");
  assert.equal(plan("remember that I like tea"), "skip");
  assert.equal(plan("my team uses Flutter for the mobile app"), "batch");
  assert.equal(plan("remember that the office closes early every Friday"), "now");
  assert.equal(plan("remember me"), "skip");
});

test("TurnBatcher runs once per N items of a key, or when idle", async () => {
  const runs: Array<[string, number]> = [];
  const b = new TurnBatcher<number>(async (k, items) => void runs.push([k, items.length]), { size: 3, idleMs: 30 });
  assert.equal(b.add("u1", 1), false);
  assert.equal(b.add("u1", 2), false);
  assert.equal(b.add("u2", 9), false);
  assert.equal(b.add("u1", 3), true); // third turn of u1 flushes
  await new Promise((r) => setTimeout(r, 5));
  assert.deepEqual(runs, [["u1", 3]]);
  assert.equal(b.pending("u2"), 1);
  await new Promise((r) => setTimeout(r, 60)); // u2 goes idle
  assert.deepEqual(runs, [["u1", 3], ["u2", 1]]);
  assert.equal(b.pending("u2"), 0);
});

// ---- follow-ups, generation caps, routing, counters -------------------------------

test("follow-ups only for substantive replies", () => {
  assert.equal(worthFollowups("Sure, happy to help!"), false);
  assert.equal(worthFollowups("x".repeat(450), intent("chitchat") as never), false);
  assert.equal(worthFollowups("x".repeat(450), intent("explain") as never), true);
  assert.equal(worthFollowups("x".repeat(450)), true);
});

test("maxTokensFor: small talk and concise profiles get a tighter cap, other modes keep theirs", () => {
  assert.equal(maxTokensFor({ intent: intent("chitchat") }), 1536);
  assert.equal(maxTokensFor({ intent: intent("chitchat", 0.3, true) }), 8192); // unsure: full cap
  assert.equal(maxTokensFor({ length: "concise" }), 4096);
  assert.equal(maxTokensFor({ mode: "design", length: "concise" }), 12288);
  assert.equal(maxTokensFor({}), 8192);
});

test("preferSmall puts the small models first and keeps the rest in order", () => {
  const out = preferSmall(["groq:openai/gpt-oss-120b", "nvidia:nvidia/nemotron-3-ultra-550b-a55b", "groq:openai/gpt-oss-20b", "ollama:gpt-oss:20b"]);
  assert.deepEqual(out, ["groq:openai/gpt-oss-20b", "ollama:gpt-oss:20b", "groq:openai/gpt-oss-120b", "nvidia:nvidia/nemotron-3-ultra-550b-a55b"]);
  assert.deepEqual(preferSmall(["groq:openai/gpt-oss-120b"]), ["groq:openai/gpt-oss-120b"]);
});

test("turn counters tally calls by kind and separate the answer from auxiliary calls", () => {
  const t = newTurnCounters();
  tally(t, "chat", "preflight", 300, 60);
  tally(t, "chat", "chat", 1500, 400);
  tally(t, "embed", "embedding");
  tally(t, "search", "web-search");
  tally(t, "search", "web-search");
  tally(t, "fetch", "web-fetch");
  tally(t, "turn", "turn-summary");
  assert.deepEqual(t, { llmCalls: 2, auxLlmCalls: 1, embedCalls: 1, searches: 2, fetches: 1, promptTokens: 1800, completionTokens: 460 });
});

// ---- turn glue --------------------------------------------------------------------

test("decideWeb: local rules win, then the preflight verdict; a failed preflight means no search", () => {
  const pre = (over: Partial<Preflight>): Preflight => ({ standalone: "x", needsWeb: null, freshness: null, queries: ["pixel 10 price"], needsKb: null, pastRef: null, via: "model", ...over });
  const base = { wantWeb: true, standalone: "Pixel 10 price", rewrittenByModel: true, decideLocal: (q: string) => decideSearchLocal(q) };
  assert.equal(decideWeb({ ...base, wantWeb: false, webLocal: null, pre: pre({ needsWeb: true }) }).search, false);
  assert.equal(decideWeb({ ...base, webLocal: { search: true, query: "q", reason: "explicit" }, pre: null }).reason, "explicit");
  const m = decideWeb({ ...base, standalone: "Pixel 10 details", webLocal: null, pre: pre({ needsWeb: true }) });
  assert.deepEqual([m.search, m.query, m.reason], [true, "pixel 10 price", "model"]);
  assert.equal(decideWeb({ ...base, standalone: "Pixel 10 details", webLocal: null, pre: pre({ needsWeb: false }) }).search, false);
  assert.equal(decideWeb({ ...base, standalone: "Pixel 10 details", webLocal: null, pre: pre({ via: "heuristic", needsWeb: true }) }).search, false);
  // The resolved standalone question can settle what the bare follow-up could not.
  assert.equal(decideWeb({ ...base, standalone: "what is the latest version of deno", webLocal: null, pre: null }).search, true);
});

test("embedTextsForTurn lists each distinct text once and nothing for small talk or attachment questions", () => {
  const o = { hasMemory: true, knowledge: true, ragRewrite: true, smallTalk: false, aboutAttachments: false, lastUser: "and the price?", standalone: "Pixel 10 price", queries: ["pixel 10 cost", "Pixel 10 price"], recallText: "Pixel 10 price" };
  assert.deepEqual(embedTextsForTurn(o), ["Pixel 10 price", "and the price?", "pixel 10 cost"]);
  assert.deepEqual(embedTextsForTurn({ ...o, smallTalk: true }), []);
  assert.deepEqual(embedTextsForTurn({ ...o, aboutAttachments: true }), []);
  assert.deepEqual(embedTextsForTurn({ ...o, hasMemory: false, knowledge: false }), []);
  assert.deepEqual(embedTextsForTurn({ ...o, knowledge: false, recallText: undefined }), ["Pixel 10 price"]);
});

// ---- compaction ----------------------------------------------------------------------

test("compactHistory reuses a summary that is a few messages behind instead of calling the model every turn", async () => {
  let calls = 0;
  const summarize = async () => (calls++, "summary text");
  const msgs = (n: number) => Array.from({ length: n }, (_, i) => ({ role: (i % 2 ? "assistant" : "user") as "user" | "assistant", content: `message ${i} ${"lorem ipsum ".repeat(250)}` }));
  const id = `chat-${Math.random()}`;
  const first = await compactHistory(msgs(14), id, 6000, { summarize });
  assert.ok(first && first.recent.length < 14);
  assert.equal(calls, 1);
  const again = await compactHistory(msgs(16), id, 6000, { summarize });
  assert.ok(again && again.summary === "summary text");
  assert.equal(calls, 1, "two more messages must not trigger another summary call");
  assert.equal(again!.recent[0].role, "user");
  assert.ok(again!.recent.length >= first!.recent.length);
  await compactHistory(msgs(30), id, 6000, { summarize });
  assert.equal(calls, 2, "a summary far behind the cut is refreshed");
});

test("system prompt keeps a stable prefix for provider prompt caching: only the final date line changes between days", async () => {
  const { buildSystemPrompt } = await import("../src/prompts/system.js");
  const a = buildSystemPrompt("default", undefined, new Date("2026-10-12"));
  const b = buildSystemPrompt("default", undefined, new Date("2026-10-13"));
  const cut = a.lastIndexOf("\n\nToday's date");
  assert.ok(cut > 1000);
  assert.equal(a.slice(0, cut), b.slice(0, cut));
  assert.notEqual(a, b);
});

test("short specific opening messages are their own title (no model call); vague ones still get one", async () => {
  const { isTitleReady, generateTitle } = await import("../src/conversations/title.js");
  assert.equal(isTitleReady("rust async runtimes compared"), true);
  assert.equal(isTitleReady("hi there friend"), false);
  assert.equal(isTitleReady("fix it for me"), false);
  assert.equal(isTitleReady("how do I deploy a flutter app to the play store"), false);
  assert.deepEqual(await generateTitle("rust async runtimes compared", "Here is a comparison..."), { title: "Rust async runtimes compared", source: "fallback" });
});
