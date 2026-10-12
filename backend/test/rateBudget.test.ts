import { test } from "node:test";
import assert from "node:assert/strict";
import { estimateTokens, hasTokenBudget, setSnapshot } from "../src/usage/rateLimits.js";
import { preferForPrompt } from "../src/llm/router.js";

const snap = (remainingTokens: number, resetInMs: number) => ({
  limitRequests: 1000, remainingRequests: 900, resetsAt: null, limitTokens: 8000,
  remainingTokens, tokensResetAt: new Date(Date.now() + resetInMs).toISOString(), at: new Date().toISOString(),
});

test("a Groq model without token room this minute is skipped", () => {
  setSnapshot("groq:test/low", snap(500, 30_000));
  setSnapshot("groq:test/high", snap(7_000, 30_000));
  const out = preferForPrompt(["groq:test/low", "groq:test/high", "nvidia:x"], 8_000);
  assert.deepEqual(out, ["groq:test/high", "nvidia:x"]);
});

test("a refilled window counts as available again", () => {
  setSnapshot("groq:test/reset", snap(0, -1_000));
  assert.equal(hasTokenBudget("groq:test/reset", estimateTokens(4_000)), true);
  assert.equal(hasTokenBudget("groq:unknown", 99_999), true);
});

test("never filters every candidate away", () => {
  setSnapshot("groq:test/only", snap(0, 30_000));
  assert.deepEqual(preferForPrompt(["groq:test/only"], 4_000), ["groq:test/only"]);
});
