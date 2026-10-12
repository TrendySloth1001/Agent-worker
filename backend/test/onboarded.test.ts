import { test } from "node:test";
import assert from "node:assert/strict";
import { onboardedPatch, publicUser, type UserRow } from "../src/auth/service.js";

const row = (onboardedAt: Date | null) =>
  ({
    id: "u1",
    email: "a@b.c",
    passwordHash: null,
    name: "Ada",
    avatarUrl: null,
    role: "user",
    limits: {},
    disabled: false,
    memoryEnabled: true,
    chatRecallEnabled: true,
    onboardedAt,
    createdAt: new Date("2026-01-01T00:00:00Z"),
    lastLoginAt: null,
  }) as UserRow;

test("publicUser reports onboarded from onboardedAt", () => {
  assert.equal(publicUser(row(null)).onboarded, false);
  assert.equal(publicUser(row(new Date())).onboarded, true);
});

test("onboardedPatch sets once, clears on false, ignores undefined", () => {
  const now = new Date("2026-10-13T10:00:00Z");
  const earlier = new Date("2026-10-01T10:00:00Z");
  assert.deepEqual(onboardedPatch(null, true, now), { onboardedAt: now });
  assert.deepEqual(onboardedPatch(earlier, true, now), {});
  assert.deepEqual(onboardedPatch(earlier, false, now), { onboardedAt: null });
  assert.deepEqual(onboardedPatch(null, false, now), {});
  assert.deepEqual(onboardedPatch(earlier, undefined, now), {});
});
