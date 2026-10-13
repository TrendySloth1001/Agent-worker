import { test } from "node:test";
import assert from "node:assert/strict";
import { MODELS } from "../src/models.js";
import { aboutModel } from "../src/modelAbout.js";

test("every registered model has a plain description", () => {
  for (const m of MODELS) {
    const a = aboutModel(m);
    assert.ok(a.maker, m.id);
    assert.ok(a.about, m.id);
    assert.ok((a.contextTokens ?? 0) > 0, m.id);
  }
});

test("an unknown family gets nothing", () => {
  assert.deepEqual(aboutModel({ id: "groq:mystery/zzz" }), {});
});
