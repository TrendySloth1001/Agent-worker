import { test } from "node:test";
import assert from "node:assert/strict";
import { ACTION_FENCE, ACTION_TYPES, deviceActionsMessage, deviceActionsSchema } from "../src/context/deviceActions.js";

test("no client support gives no message", () => {
  assert.equal(deviceActionsMessage(undefined), null);
});

test("the message teaches the fenced block and every action type", () => {
  const m = deviceActionsMessage(deviceActionsSchema.parse({}))!;
  assert.match(m, new RegExp("```" + ACTION_FENCE));
  for (const t of ACTION_TYPES) assert.match(m, new RegExp(`"type":"${t}"`));
  assert.match(m, /nothing happens until the user taps Confirm/);
  assert.doesNotMatch(m, /local time now/);
});

test("local time is passed through for relative times", () => {
  const m = deviceActionsMessage(deviceActionsSchema.parse({ localTime: "2026-10-13T14:05:00+02:00" }))!;
  assert.match(m, /local time now: 2026-10-13T14:05:00\+02:00/);
});

test("schema caps the local time", () => {
  assert.equal(deviceActionsSchema.safeParse({ localTime: "x".repeat(41) }).success, false);
});
