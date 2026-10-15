import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { AUX_POOL, auxModels } from "../src/llm/auxPool.js";
import { clearCooldown, setCooldown } from "../src/models.js";
import { resetQuota } from "../src/llm/quota.js";
import { config } from "../src/config.js";

beforeEach(() => {
  for (const id of AUX_POOL) clearCooldown(id);
  resetQuota();
});

test("the aux pool holds only small models, never the reply models", () => {
  for (const id of AUX_POOL) assert.match(id, /20b|lightning/);
});

test("a cooling model is left out of the aux pool", () => {
  const before = auxModels(100, AUX_POOL);
  if (before.length === 0 || !config.groqApiKey) return; // no provider keys configured in this environment
  setCooldown(before[0], 60_000);
  assert.ok(!auxModels(100, AUX_POOL).includes(before[0]));
});
