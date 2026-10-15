import { test } from "node:test";
import assert from "node:assert/strict";
import { runRoundTable, seat, type TableDeps, type TableEvent } from "../src/table/roundTable.js";
import { UpstreamError } from "../src/providers.js";

const A1 = "ollama:nemotron-3-ultra";
const A2 = "nvidia:nvidia/nemotron-3-ultra-550b-a55b";
const B1 = "groq:openai/gpt-oss-120b";
const B2 = "ollama:gpt-oss:120b";
const ALL = [A1, A2, B1, B2];

type Call = { model: string; purpose?: string; maxTokens?: number; maxChars?: number };

function deps(over: Partial<TableDeps> = {}, fail: (m: string) => boolean = () => false): { deps: TableDeps; calls: Call[] } {
  const calls: Call[] = [];
  const d: TableDeps = {
    candidates: async () => ALL,
    headroom: () => true,
    ask: async (model, _msgs, opts) => {
      calls.push({ model, purpose: opts.purpose, maxTokens: opts.maxTokens, maxChars: opts.maxChars });
      if (fail(model)) throw new UpstreamError(429, "rate limited");
      return `TL;DR: answer from ${model}.\nBody.`;
    },
    ...over,
  };
  return { deps: d, calls };
}

const input = (events: TableEvent[] = []) => ({
  history: [{ role: "user" as const, content: "Explain TLS 1.3" }],
  context: null,
  question: "Explain TLS 1.3",
  preamble: "",
  promptChars: 400,
  vision: null,
  signal: new AbortController().signal,
  emit: (e: TableEvent) => events.push(e),
});

test("table seats two models on different providers", async () => {
  const plans = await seat(400, null, deps().deps);
  assert.equal(plans.length, 2);
  const providers = plans.map((p) => p.models[0].split(":")[0]);
  assert.notEqual(providers[0], providers[1]);
});

test("table seats avoid a provider with no headroom", async () => {
  const d = deps({ headroom: (id) => !id.startsWith("groq:") }).deps;
  const plans = await seat(400, null, d);
  assert.ok(plans.every((p) => !p.models[0].startsWith("groq:")));
  assert.notEqual(plans[0].models[0].split(":")[0], plans[1].models[0].split(":")[0]);
});

test("table: two capped drafts then straight to the chair, no judge or review calls", async () => {
  const events: TableEvent[] = [];
  const { deps: d, calls } = deps();
  const run = await runRoundTable(input(events), d);
  assert.ok(run);
  assert.equal(calls.length, 2);
  assert.ok(calls.every((c) => c.purpose === "table-draft"));
  assert.ok(calls.every((c) => (c.maxTokens ?? 9999) <= 700 && (c.maxChars ?? 9999) <= 2400));
  assert.match(run.chairMessage.content, /Draft A/);
  assert.match(run.chairMessage.content, /Draft B/);
  assert.ok(!events.some((e) => (e.phase as string) === "checking" || (e.phase as string) === "reviewing"));
  assert.ok(events.some((e) => e.phase === "synthesizing"));
  const t = run.finish(A1, 1, []);
  assert.equal(t.seats.length, 2);
  assert.deepEqual(t.reviews, []);
  assert.equal(t.consensus, "agreed");
  assert.equal(t.calls, 3);
  assert.equal(run.finish(A1, 1, ["x?"]).consensus, "disputed");
});

test("table: a failing drafter falls back to a model on another provider", async () => {
  const { deps: d, calls } = deps({}, (m) => m === B1);
  const run = await runRoundTable(input(), d);
  assert.ok(run);
  assert.ok(calls.some((c) => c.model === B1));
  assert.equal(calls.filter((c) => c.model !== B1).length, 2);
});

test("table: gives up (null, normal answer) when a drafter cannot be replaced", async () => {
  const { deps: d } = deps({ candidates: async () => [A1, B1] }, (m) => m === B1);
  assert.equal(await runRoundTable(input(), d), null);
});

test("table: unexpected internal errors give up instead of failing the turn", async () => {
  const { deps: d } = deps({
    candidates: async () => {
      throw new Error("boom");
    },
  });
  assert.equal(await runRoundTable(input(), d), null);
});
