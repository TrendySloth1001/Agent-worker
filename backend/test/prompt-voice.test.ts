import { test } from "node:test";
import assert from "node:assert/strict";
import { buildSystemPrompt, TONES, LENGTHS } from "../src/prompts/system.js";

test("voice rules are conditional, not templated", () => {
  const p = buildSystemPrompt("default");
  assert.doesNotMatch(p, /Quick comparison/);
  assert.doesNotMatch(p, /begin most bullets/);
  assert.match(p, /only for long/);
  assert.match(p, /Great question/); // listed as a banned filler phrase
});

test("every tone and length yields a distinct section", () => {
  const tones = new Set(TONES.map((tone) => buildSystemPrompt("default", { tone })));
  const lengths = new Set(LENGTHS.map((length) => buildSystemPrompt("default", { length })));
  assert.equal(tones.size, TONES.length);
  assert.equal(lengths.size, LENGTHS.length);
});
