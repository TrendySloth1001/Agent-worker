import { test } from "node:test";
import assert from "node:assert/strict";
import {
  apkKeyFor,
  canDelete,
  createBody,
  decideUpdate,
  duplicateBuild,
  escalatedKind,
  isRequired,
  minSupported,
  mostSevere,
  parseOr400,
  patchBody,
  pickLatest,
  publishedAtFor,
  type LiveRelease,
} from "../src/ota/logic.js";
import { AppError } from "../src/util/errors.js";

const rel = (build: number, kind: LiveRelease["kind"], min: number | null = null): LiveRelease => ({ build, kind, minSupportedBuild: min });

test("mostSevere: critical > major > feature > patch", () => {
  assert.equal(mostSevere(["patch", "feature"]), "feature");
  assert.equal(mostSevere(["feature", "critical", "major"]), "critical");
  assert.equal(mostSevere(["patch", "major", "feature"]), "major");
  assert.equal(mostSevere([]), "patch");
});

test("pickLatest: highest build above the client's, else null", () => {
  const live = [rel(24, "patch"), rel(27, "feature"), rel(26, "major")];
  assert.equal(pickLatest(live, 25)?.build, 27);
  assert.equal(pickLatest(live, 27), null);
  assert.equal(pickLatest([], 1), null);
});

test("escalatedKind: only releases newer than the client count", () => {
  const live = [rel(30, "patch"), rel(28, "critical"), rel(20, "major")];
  assert.equal(escalatedKind(live, 25), "critical");
  assert.equal(escalatedKind(live, 28), "patch");
  assert.equal(escalatedKind(live, 10), "critical");
});

test("minSupported: max over live releases, null when none", () => {
  assert.equal(minSupported([rel(3, "patch"), rel(4, "patch", 2), rel(5, "patch", 3)]), 3);
  assert.equal(minSupported([rel(3, "patch")]), null);
  assert.equal(minSupported([]), null);
});

test("isRequired: critical or below the minimum supported build", () => {
  assert.equal(isRequired("critical", null, 25), true);
  assert.equal(isRequired("feature", null, 25), false);
  assert.equal(isRequired("patch", 26, 25), true);
  assert.equal(isRequired("patch", 25, 25), false);
  assert.equal(isRequired(null, 30, 25), true); // below minimum even with nothing newer
  assert.equal(isRequired(null, null, 25), false);
});

test("decideUpdate: escalation, required and no-update cases", () => {
  const live = [rel(26, "patch"), rel(27, "feature", 26)];
  const d = decideUpdate(live, 25);
  assert.equal(d.latest?.build, 27);
  assert.equal(d.kind, "feature");
  assert.equal(d.minSupportedBuild, 26);
  assert.equal(d.required, true);

  const esc = decideUpdate([rel(26, "critical"), rel(27, "patch")], 25);
  assert.equal(esc.latest?.build, 27);
  assert.equal(esc.kind, "critical");
  assert.equal(esc.required, true);

  const none = decideUpdate(live, 27);
  assert.equal(none.latest, null);
  assert.equal(none.kind, null);
  assert.equal(none.required, false);
});

test("apkKeyFor", () => {
  assert.equal(apkKeyFor(25, "1.7.0"), "releases/25/sparky-1.7.0-arm64.apk");
});

const ok = { version: "1.7.0", build: "25", kind: "feature", title: "Hello", notes: JSON.stringify(["a", "b"]) };

test("createBody: accepts a valid form and applies defaults", () => {
  const b = parseOr400(createBody, ok);
  assert.equal(b.build, 25);
  assert.deepEqual(b.notes, ["a", "b"]);
  assert.equal(b.status, "draft");
  assert.equal(b.minSupportedBuild, undefined);
  const live = parseOr400(createBody, { ...ok, status: "live", minSupportedBuild: "20" });
  assert.equal(live.status, "live");
  assert.equal(live.minSupportedBuild, 20);
});

test("createBody: rejects bad kind, version, notes, status", () => {
  const bad = (o: object) => assert.throws(() => parseOr400(createBody, { ...ok, ...o }), (e) => e instanceof AppError && e.status === 400);
  bad({ kind: "huge" });
  bad({ version: "1.7" });
  bad({ version: "v1.7.0" });
  bad({ version: "1.7.0+25" });
  bad({ build: "abc" });
  bad({ build: "0" });
  bad({ notes: "not json" });
  bad({ notes: JSON.stringify({ a: 1 }) });
  bad({ notes: JSON.stringify(["1", "2", "3", "4", "5", "6", "7"]) });
  bad({ status: "pulled" });
});

test("createBody: six notes are fine", () => {
  const b = parseOr400(createBody, { ...ok, notes: JSON.stringify(["1", "2", "3", "4", "5", "6"]) });
  assert.equal(b.notes.length, 6);
});

test("duplicate build is a 409", () => {
  const e = duplicateBuild(25);
  assert.equal(e.status, 409);
  assert.equal(e.code, "conflict");
});

test("patchBody: partial, null clears minSupportedBuild, rejects junk", () => {
  assert.deepEqual(parseOr400(patchBody, { minSupportedBuild: null }), { minSupportedBuild: null });
  assert.deepEqual(parseOr400(patchBody, { status: "pulled", kind: "major" }), { status: "pulled", kind: "major" });
  assert.throws(() => parseOr400(patchBody, { status: "gone" }), AppError);
  assert.throws(() => parseOr400(patchBody, { kind: "x" }), AppError);
  assert.throws(() => parseOr400(patchBody, { notes: ["1", "2", "3", "4", "5", "6", "7"] }), AppError);
  assert.throws(() => parseOr400(patchBody, { build: 3 }), AppError);
});

test("canDelete / publishedAtFor", () => {
  assert.equal(canDelete("draft"), true);
  assert.equal(canDelete("pulled"), true);
  assert.equal(canDelete("live"), false);
  const now = new Date("2026-01-01T00:00:00Z");
  const earlier = new Date("2025-01-01T00:00:00Z");
  assert.equal(publishedAtFor("draft", "live", null, now), now);
  assert.equal(publishedAtFor("live", "live", earlier, now), earlier);
  assert.equal(publishedAtFor("live", "pulled", earlier, now), earlier);
  assert.equal(publishedAtFor("draft", undefined, null, now), null);
});
