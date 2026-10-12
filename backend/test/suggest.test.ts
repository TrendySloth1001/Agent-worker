import { test } from "node:test";
import assert from "node:assert/strict";
import { cleanCompletion, cleanNextWords, endsInUrl, parseFollowups, parseJsonObject, parseStarters } from "../src/assist/suggest.js";

test("parseFollowups reads fenced JSON, dedupes and caps at 3", () => {
  const raw = '```json\n{"followups":["Explain more","explain more","Give an example","Why?","Summarize"]}\n```';
  assert.deepEqual(parseFollowups(raw), ["Explain more", "Give an example", "Why?"]);
});

test("parseFollowups tolerates garbage and think blocks", () => {
  assert.deepEqual(parseFollowups("no json here"), []);
  assert.deepEqual(parseFollowups('<think>{"x":1}</think>{"followups":["a b"]}'), ["a b"]);
});

test("parseStarters caps at 4 and drops long items", () => {
  const long = "x".repeat(100);
  assert.deepEqual(parseStarters(JSON.stringify({ prompts: ["a", long, "b", "c", "d", "e"] })), ["a", "b", "c", "d"]);
});

test("parseJsonObject rejects arrays", () => {
  assert.equal(parseJsonObject("[1,2]"), null);
});

test("cleanCompletion removes repeated input and keeps spacing", () => {
  assert.equal(cleanCompletion("How do I bak", "bake a cake?"), "e a cake?");
  assert.equal(cleanCompletion("How do I bake ", " a cake?"), "a cake?");
  assert.equal(cleanCompletion("Hello, ", "Hello, world"), "world");
  assert.equal(cleanCompletion("Hi.", "How are you?"), " How are you?");
  assert.equal(cleanCompletion("Hi", "\n"), "");
  assert.equal(cleanCompletion("Hi", 5), "");
  assert.equal(cleanCompletion("how does retrieval", "work?", false), " work?");
  assert.equal(cleanCompletion("how does retriev", " al work?", true), "al work?");
  assert.equal(cleanCompletion("abc", "line one\nline two"), "line one");
});

test("cleanNextWords keeps single words only", () => {
  assert.deepEqual(cleanNextWords(["the", "two words", "a", "the"]), ["the", "a"]);
  assert.deepEqual(cleanNextWords("nope"), []);
});

test("endsInUrl", () => {
  assert.equal(endsInUrl("see https://exa"), true);
  assert.equal(endsInUrl("see https://example.com now"), false);
  assert.equal(endsInUrl("www.foo"), true);
  assert.equal(endsInUrl("plain text"), false);
});
