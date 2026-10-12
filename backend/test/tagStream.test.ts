import { test } from "node:test";
import assert from "node:assert/strict";
import { TagStream } from "../src/web/tagStream.js";

const run = (chunks: string[]) => {
  const t = new TagStream();
  return chunks.map((c) => t.push(c)).join("") + t.flush();
};

test("think blocks are removed, also when tags are split across chunks", () => {
  assert.equal(run(["<think>plan</think>Hello"]), "Hello");
  assert.equal(run(["<thi", "nk>hidden", " more</th", "ink>\n\nAnswer [W1]"]), "Answer [W1]");
  assert.equal(run(["a < b and <thin", "g> c"]), "a < b and <thing> c");
});

test("a lone closing think tag at the start drops the reasoning before it", () => {
  assert.equal(run(["reasoning...</think>Answer"]), "Answer");
});

test("an unterminated think block is dropped; citations still normalize", () => {
  assert.equal(run(["Hi<think>never closed"]), "Hi");
  assert.equal(run(["See [K1, W2]"]), "See [K1][W2]");
});
