/**
 * Deterministic turn-cost simulation: representative turns run through runChat
 * with mocked providers, counting model sends and the tokens put on the wire.
 * Budgets here are the regression guard for model-call cost and 429 cascades.
 */
import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { MODELS, clearCooldown } from "../src/models.js";
import { ChatFailure, runChat, type RunHooks, type RunResult } from "../src/llm/router.js";
import { estimateRequestTokens } from "../src/llm/budget.js";
import { resetQuota } from "../src/llm/quota.js";
import { UpstreamError, type Message, type StreamHandle } from "../src/providers.js";
import { buildSystemPrompt, promptNeeds } from "../src/prompts/system.js";
import { analyze } from "../src/nlp/index.js";

const TURNS = {
  casual: "hey how are you",
  factual: "who won the 2018 world cup and what was the score?",
  coding: "write a python function to merge two sorted lists and explain complexity",
} as const;
type TurnKind = keyof typeof TURNS;

const ALL = MODELS.map((m) => m.id);

beforeEach(() => {
  for (const id of ALL) clearCooldown(id);
  resetQuota();
});

/** The system prompt a turn of this kind would carry (same selection as routes/chat.ts). */
function promptFor(kind: TurnKind): Message[] {
  const text = TURNS[kind];
  const nlp = analyze(text, [], { hasImages: false, hasAttachments: false });
  const needs = promptNeeds(text, false, nlp.intent);
  return [
    { role: "system", content: buildSystemPrompt("default" as never, undefined, undefined, needs) },
    { role: "user", content: text },
  ];
}

type Tally = { sends: number; tokens: number; failed429: number };

/** A provider that answers "ok" unless [fails] says the model is rate limited. */
function mockStream(tally: Tally, fails: (id: string) => boolean) {
  return async (id: string, messages: Message[]): Promise<StreamHandle> => {
    tally.sends++;
    tally.tokens += estimateRequestTokens(messages, 8192);
    if (fails(id)) {
      tally.failed429++;
      throw new UpstreamError(429, "Rate limit reached for model: tokens per minute (TPM). Please try again in 1m0s");
    }
    async function* gen() {
      yield "Hello there.";
    }
    return { tokens: gen(), usage: { promptTokens: 10, completionTokens: 3, finishReason: "stop", completed: true } };
  };
}

const hooks: RunHooks = { onQueued() {}, onModel() {}, onDelta() {}, onReset() {}, onFallback() {} };

async function runTurn(kind: TurnKind, tally: Tally, fails: (id: string) => boolean, candidates = ALL): Promise<RunResult | ChatFailure> {
  try {
    return await runChat(candidates, promptFor(kind), new AbortController().signal, hooks, true, { maxTokens: 8192, stream: mockStream(tally, fails) as never });
  } catch (e) {
    if (e instanceof ChatFailure) return e;
    throw e;
  }
}

test("healthy providers: one send per turn", async () => {
  const rows: string[] = [];
  for (const kind of Object.keys(TURNS) as TurnKind[]) {
    const t: Tally = { sends: 0, tokens: 0, failed429: 0 };
    const r = await runTurn(kind, t, () => false);
    assert.ok(!(r instanceof ChatFailure));
    assert.ok(t.sends <= 2, `${kind}: ${t.sends} sends`);
    rows.push(`${kind}: sends=${t.sends} tokens=${t.tokens}`);
  }
  console.log(`[turn-cost] healthy  ${rows.join(" | ")}`);
});

test("two providers saturated: the turn is still answered within 3 sends", async () => {
  const t: Tally = { sends: 0, tokens: 0, failed429: 0 };
  const r = await runTurn("factual", t, (id) => id.startsWith("groq:") || id.startsWith("nvidia:"));
  console.log(`[turn-cost] groq+nvidia saturated: sends=${t.sends} tokens=${t.tokens}`);
  assert.ok(!(r instanceof ChatFailure));
  assert.ok(t.sends <= 3);
});

test("429 storm on the first candidates: a cold turn sends at most 3 full prompts", async () => {
  // Everything except one late Ollama model is rate limited.
  const open = new Set(["ollama:nemotron-3-ultra"]);
  const t: Tally = { sends: 0, tokens: 0, failed429: 0 };
  await runTurn("coding", t, (id) => !open.has(id));
  console.log(`[turn-cost] storm cold turn: sends=${t.sends} tokens=${t.tokens} 429s=${t.failed429}`);
  assert.ok(t.sends <= 3, `${t.sends} sends`);
});

test("429 storm: later turns skip cooling models and cost <= 4 sends", async () => {
  const open = new Set(["ollama:nemotron-3-ultra"]);
  const total: Tally = { sends: 0, tokens: 0, failed429: 0 };
  let answered = 0;
  let maxSends = 0;
  const kinds: TurnKind[] = ["casual", "factual", "coding", "casual", "factual", "coding"];
  for (const kind of kinds) {
    const t: Tally = { sends: 0, tokens: 0, failed429: 0 };
    const r = await runTurn(kind, t, (id) => !open.has(id));
    if (!(r instanceof ChatFailure)) answered++;
    maxSends = Math.max(maxSends, t.sends);
    total.sends += t.sends;
    total.tokens += t.tokens;
    total.failed429 += t.failed429;
  }
  console.log(`[turn-cost] storm 6 turns: sends=${total.sends} (${(total.sends / kinds.length).toFixed(2)}/turn) tokens=${total.tokens} (${Math.round(total.tokens / kinds.length)}/turn) 429s=${total.failed429} answered=${answered}/6 maxSends=${maxSends}`);
  assert.ok(maxSends <= 4, `a storm turn used ${maxSends} sends`);
  assert.ok(answered >= 4, `only ${answered}/6 turns answered`);
  assert.ok(total.sends / kinds.length <= 3, "average sends per storm turn");
});
