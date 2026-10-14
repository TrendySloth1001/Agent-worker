import { test } from "node:test";
import assert from "node:assert/strict";
import { isFactualLookup } from "../src/web/factual.js";
import { decideSearchLocal } from "../src/web/searchDecision.js";
import { preferForFacts } from "../src/llm/router.js";
import { buildSystemPrompt } from "../src/prompts/system.js";
import { toolsNote } from "../src/toggles/suggest.js";
import { TagStream } from "../src/web/tagStream.js";
import { score } from "../scripts/factual-score.js";

test("factual lookups about named things are detected (English and Hinglish)", () => {
  for (const q of [
    "Who wrote the Hindi novel Godan?",
    "Summarize the plot of the 2019 novel 'The Glass Cartographer of Lahnbury'.",
    "Give me the API reference for the npm package 'quantum-leftpad-ng'.",
    "What does the --turbo-merge flag do in git commit?",
    "Explain the Sharmaji-Lindqvist theorem in algebraic topology.",
    "Bhai Chandrayaan-3 moon pe kab land hua tha?",
    "Rupee ka symbol kisne design kiya tha?",
    "How much does the Zorvath X3 Pro cost in India?",
  ]) assert.equal(isFactualLookup(q), true, q);
});

test("coding, writing, conceptual and chit-chat messages are not factual lookups", () => {
  for (const q of [
    "hey how are you doing today",
    "Write a function that reverses a string in Python",
    "How do I center a div in CSS?",
    "explain how recursion works",
    "what is the difference between let and const",
    "Fix this bug in my code please",
    "Can you proofread my cover letter",
  ]) assert.equal(isFactualLookup(q), false, q);
});

test("Auto searches for a factual lookup, but not when the user's own data is meant", () => {
  assert.equal(decideSearchLocal("Who wrote the Hindi novel Godan?")?.reason, "factual");
  assert.equal(decideSearchLocal("Write a function that reverses a string")?.search ?? false, false);
});

test("factual turns try big-knowledge models first and the 20B ones last, dropping nothing", () => {
  const all = ["groq:openai/gpt-oss-120b", "groq:openai/gpt-oss-20b", "nvidia:nvidia/nemotron-3-ultra-550b-a55b", "ollama:gemma4:31b"];
  const out = preferForFacts(all);
  assert.deepEqual(out, ["nvidia:nvidia/nemotron-3-ultra-550b-a55b", "groq:openai/gpt-oss-120b", "ollama:gemma4:31b", "groq:openai/gpt-oss-20b"]);
  assert.deepEqual([...out].sort(), [...all].sort());
});

test("the system prompt carries the accuracy rules and today's date", () => {
  const p = buildSystemPrompt("default", undefined, new Date("2026-10-14"));
  assert.match(p, /Today's date is 2026-10-14/);
  assert.match(p, /knowledge has a cutoff/);
  assert.match(p, /don't recognize/i);
  assert.match(p, /Check the premise/);
  assert.match(p, /Exact figures/);
});

test("with no web run, the tools note tells the model not to guess", () => {
  const off = toolsNote({ web: "off", kb: "off" } as never);
  const none = toolsNote({ web: "auto-none", kb: "off" } as never);
  for (const n of [off, none]) assert.match(n, /only what you are sure of/);
});

test("citation tags that point at no provided source are stripped", () => {
  const none = new TagStream(new Set());
  assert.equal(none.push("Canberra is the capital [W1].") + none.flush(), "Canberra is the capital.");
  const some = new TagStream(new Set(["W1"]));
  assert.equal(some.push("It is X [W1] and Y [W7].") + some.flush(), "It is X [W1] and Y.");
});

test("eval scoring: correct, abstained, confident-wrong", () => {
  const item = { id: "t", cat: "recent", q: "", expected: "", accept: ["leo xiv"], reject: ["francis is the"], abstain_ok: true };
  assert.equal(score(item, "The current pope is Leo XIV."), "correct");
  assert.equal(score(item, "I'm not sure who it is right now."), "abstained_ok");
  assert.equal(score(item, "Pope Francis is the current pope."), "confident_wrong");
  const fake = { id: "f", cat: "nonexistent", q: "", expected: "", accept: [], abstain_ok: true };
  assert.equal(score(fake, "I don't recognize that novel."), "abstained_ok");
  assert.equal(score(fake, "The novel follows a mapmaker who travels to Lahnbury."), "confident_wrong");
});
