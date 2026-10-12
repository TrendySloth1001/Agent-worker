import { test } from "node:test";
import assert from "node:assert/strict";
import { BASE_COOLDOWN_MS, HealthTracker, MAX_COOLDOWN_MS } from "../src/llm/health.js";
import { applyCooldown } from "../src/llm/router.js";
import { cooldownUntil, clearCooldown } from "../src/models.js";
import { UpstreamError } from "../src/providers.js";

test("circuit breaker: backoff doubles from 30 s up to the cap", () => {
  assert.equal(HealthTracker.backoff(1), BASE_COOLDOWN_MS);
  assert.equal(HealthTracker.backoff(2), BASE_COOLDOWN_MS * 2);
  assert.equal(HealthTracker.backoff(3), BASE_COOLDOWN_MS * 4);
  assert.equal(HealthTracker.backoff(40), MAX_COOLDOWN_MS);
});

test("circuit breaker: opens on failure, half-opens after the wait, resets on success", () => {
  let now = 1_000_000;
  const h = new HealthTracker(() => now);
  assert.equal(h.isOpen("m"), false);
  assert.equal(h.failure("m"), BASE_COOLDOWN_MS);
  assert.equal(h.isOpen("m"), true);
  now += BASE_COOLDOWN_MS + 1; // half-open: tried again
  assert.equal(h.isOpen("m"), false);
  assert.equal(h.failure("m"), BASE_COOLDOWN_MS * 2); // failed probe backs off further
  assert.equal(h.consecutiveFailures("m"), 2);
  h.success("m");
  assert.equal(h.isOpen("m"), false);
  assert.equal(h.failure("m"), BASE_COOLDOWN_MS); // streak was reset
});

test("circuit breaker: a long-quiet failure streak is forgotten", () => {
  let now = 0;
  const h = new HealthTracker(() => now);
  h.failure("m");
  h.failure("m");
  now += 60 * 60_000;
  assert.equal(h.failure("m"), BASE_COOLDOWN_MS);
});

test("applyCooldown: timeouts and 5xx cool a model down with growing backoff; 400 does not", () => {
  const id = "test:breaker-model";
  clearCooldown(id);
  applyCooldown(id, new UpstreamError(400, "bad"));
  assert.equal(cooldownUntil(id), null);

  applyCooldown(id, new UpstreamError(0, "timeout waiting for response"));
  const first = cooldownUntil(id);
  assert.ok(first && first - Date.now() <= BASE_COOLDOWN_MS);

  applyCooldown(id, new UpstreamError(503, "unavailable"));
  const second = cooldownUntil(id);
  assert.ok(second && second - Date.now() > BASE_COOLDOWN_MS, "second failure waits longer");
  clearCooldown(id);
});
