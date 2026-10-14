import { test } from "node:test";
import assert from "node:assert/strict";
import { buildSystemPrompt, buildContextMessage, TONES, LENGTHS } from "../src/prompts/system.js";

const NOW = new Date("2026-10-14T12:00:00Z");
const LEAN = { html: false, github: false, widgetExamples: false };
const build = (profile?: Parameters<typeof buildSystemPrompt>[1], needs: Parameters<typeof buildSystemPrompt>[3] = LEAN) =>
  buildSystemPrompt("default", profile, NOW, needs);

test("voice rules are conditional, not templated", () => {
  const p = build();
  assert.doesNotMatch(p, /Quick comparison\b(?!\*\*)/);
  assert.doesNotMatch(p, /begin most bullets/);
  assert.match(p, /only closes a long/);
  assert.match(p, /Great question/); // listed as a banned filler phrase
});

test("every tone and length yields a distinct section", () => {
  const tones = new Set(TONES.map((tone) => build({ tone })));
  const lengths = new Set(LENGTHS.map((length) => build({ length })));
  assert.equal(tones.size, TONES.length);
  assert.equal(lengths.size, LENGTHS.length);
});

test("the reply guidance carries each key rule", () => {
  const p = build();
  const rules: [string, RegExp][] = [
    ["answer first", /Answer first\. The first sentence answers/],
    ["length follows the question", /Length follows the question/],
    ["prose by default", /Prose by default, in short paragraphs/],
    ["commit to a decision", /commit in the first sentence/],
    ["lists only when list-shaped", /Numbered list: steps in a fixed order/],
    ["headings only for long answers", /Headings: only for long answers with three or more distinct parts/],
    ["no bold pseudo-headings", /never a line of \*\*bold\*\* standing in for a heading/],
    ["tables for comparisons", /Table: three or more items compared/],
    ["language and script mirroring", /answer only in Latin letters/],
    ["uncertainty said once", /Uncertainty: say it once/],
    ["no generic endings", /no "let me know if\.\.\."/],
    ["ASCII citation tags", /plain ASCII square brackets/],
    ["TeX delimiters", /Never use \\\( \\\) or \\\[ \\\] delimiters/],
    ["code fences with language", /fenced blocks with a language tag/],
  ];
  for (const [name, re] of rules) assert.match(p, re, name);
});

test("style modifiers adjust the base and never contradict it", () => {
  for (const length of LENGTHS) {
    const p = build({ length });
    assert.match(p, new RegExp(`Response length: ${length.toUpperCase()}\\.`));
    // Only one length section is ever present.
    assert.equal((p.match(/Response length:/g) ?? []).length, 1);
  }
  for (const tone of TONES) assert.equal((build({ tone }).match(/Tone: /g) ?? []).length, 1);
  // Tone sections talk about voice only: none may dictate structure or length.
  const tonePrompts = TONES.map((tone) => build({ tone }).split("\n\n").find((s) => s.startsWith("Tone:")) ?? "");
  for (const t of tonePrompts) assert.doesNotMatch(t, /\b(headings?|bullets?|lists?|tables?|paragraphs?)\b/i);
  // Concise bans structure; the base already makes structure the exception.
  assert.match(build({ length: "concise" }), /No headings, tables or widgets/);
  assert.match(build({ length: "balanced" }), /two to four short paragraphs/);
});

test("assembled prompt per style (section snapshot)", () => {
  const sections = (p: string) => p.split("\n\n").filter((s) => /^(Response length|Tone):/.test(s));
  assert.deepEqual(sections(build({ length: "concise", tone: "direct" })), [
    "Response length: CONCISE. Scale every length above down: the answer or fix, then at most a line or two of essential why, usually under about 80 words (code excepted). No headings, tables or widgets, no alternatives or examples unless critical; one small snippet beats prose.",
    "Tone: direct. Verdict first, then the reasons in as few words as possible. No pleasantries, hedging or warm-ups; blunt but never rude.",
  ]);
  assert.deepEqual(sections(build()), [
    "Response length: DETAILED. Give depth where the question has it: the direct answer, the reasoning, a worked example and the pitfalls that matter, with headings only if the answer is truly multi-part. Chit-chat, simple facts, tips, comparisons and drafts stay compact even here. Never pad.",
  ]);
});

test("prompt size budget", () => {
  // Characters; ~4 per token. Guards against the reply rules growing back.
  const full = build(undefined, { html: true, github: true, widgetExamples: true });
  const lean = build();
  const compact = build(undefined, { compact: true });
  assert.ok(full.length < 26_000, `full prompt ${full.length}`);
  assert.ok(lean.length < 18_000, `lean prompt ${lean.length}`);
  assert.ok(compact.length < 12_500, `compact prompt ${compact.length}`);
  for (const length of LENGTHS) for (const tone of TONES) assert.ok(build({ length, tone }).length < 18_500);
});

test("citation rule keeps square-bracket tags", () => {
  const msg = buildContextMessage([], [{ id: "W1", title: "t", url: "https://x.test", text: "body" }]) ?? "";
  assert.match(msg, /end every sentence that uses a source with its tag/);
  assert.match(msg, /\[W2\]/);
});
