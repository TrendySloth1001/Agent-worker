import { test } from "node:test";
import assert from "node:assert/strict";
import { fallbackModels, isUpstreamBusy } from "../src/llm/stream-openrouter.js";
import { UpstreamError } from "../src/providers.js";

test("free OpenRouter models get up to two other free fallbacks", () => {
  const alts = fallbackModels("google/gemma-4-31b-it:free");
  assert.ok(alts.length >= 1 && alts.length <= 2);
  assert.ok(alts.every((m) => m.endsWith(":free") && m !== "google/gemma-4-31b-it:free"));
  assert.deepEqual(fallbackModels("openai/gpt-4o"), []);
});

test("upstream saturation retries; our own quota and timeouts do not", () => {
  assert.equal(isUpstreamBusy(new UpstreamError(429, "Provider returned error")), true);
  assert.equal(isUpstreamBusy(new UpstreamError(502, "bad gateway")), true);
  assert.equal(isUpstreamBusy(new UpstreamError(429, "Rate limit exceeded: free-models-per-day")), false);
  assert.equal(isUpstreamBusy(new UpstreamError(0, "timeout waiting for response")), false);
  assert.equal(isUpstreamBusy(new UpstreamError(401, "bad key")), false);
});
