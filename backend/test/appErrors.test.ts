import { after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import type { AddressInfo } from "node:net";
import express from "express";
import { config } from "../src/config.js";
import { closeDb, db, initDb, onDbUp } from "../src/db/prisma.js";
import { appRouter } from "../src/routes/app.js";
import { adminErrorsRouter, adminHealthRouter } from "../src/routes/adminErrors.js";
import { errorMiddleware } from "../src/util/errors.js";
import {
  SAMPLES_PER_BUILD,
  USER_DAILY_SAMPLE_CAP,
  crashFreeRate,
  errorsBody,
  fingerprintOf,
  mergeOutcome,
  prepareError,
  retentionCutoff,
  scrubStack,
  scrubText,
  sessionsBody,
  shouldStoreSample,
  significantFrames,
  statusAfterHit,
  type ErrorItem,
} from "../src/ota/errorsLogic.js";
import { buildsHealth, groupDetail, ingestErrors, ingestSessions, listGroups, setGroupStatus, sweepAppErrors } from "../src/ota/errorsService.js";

// ---- pure: fingerprints --------------------------------------------------------------

const DART_A = `#0      _Foo.bar (package:app/features/chat/foo.dart:42:7)
#1      State.setState (package:flutter/src/widgets/framework.dart:1190:9)
#2      _Baz.go (package:app/core/baz.dart:10:3)
#3      _Qux.run (package:app/core/qux.dart:99:1)
#4      _Deep.x (package:app/core/deep.dart:5:5)`;
// Same error after unrelated edits moved lines/columns around.
const DART_B = DART_A.replace(":42:7", ":57:9").replace(":10:3", ":12:3").replace("1190:9", "1203:9");

test("fingerprint: line and column numbers do not change the group", () => {
  assert.equal(fingerprintOf("dart", "StateError", DART_A), fingerprintOf("dart", "StateError", DART_B));
});

test("fingerprint: type, kind and top app frames do", () => {
  const base = fingerprintOf("dart", "StateError", DART_A);
  assert.notEqual(base, fingerprintOf("dart", "RangeError", DART_A));
  assert.notEqual(base, fingerprintOf("platform", "StateError", DART_A));
  assert.notEqual(base, fingerprintOf("dart", "StateError", DART_A.replace("foo.dart", "other.dart")));
  // A fourth app frame is beyond the top 3 and ignored.
  assert.equal(base, fingerprintOf("dart", "StateError", DART_A.replace("deep.dart", "else.dart")));
});

test("fingerprint: framework frames beyond the first are ignored", () => {
  const withAsync = `#0      _Foo.bar (package:app/features/chat/foo.dart:42:7)
#1      _asyncThenWrapperHelper (dart:async/zone.dart:11:3)
#2      _Baz.go (package:app/core/baz.dart:10:3)
#3      _Qux.run (package:app/core/qux.dart:99:1)`;
  const without = `#0      _Foo.bar (package:app/features/chat/foo.dart:42:7)
#1      _Baz.go (package:app/core/baz.dart:10:3)
#2      _Qux.run (package:app/core/qux.dart:99:1)`;
  assert.deepEqual(significantFrames(withAsync), significantFrames(without));
});

test("fingerprint: a leading framework frame is kept, then up to 3 app frames", () => {
  const f = significantFrames(`#0 Object.noSuchMethod (dart:core-patch/object_patch.dart:38:5)\n${DART_A}`);
  assert.equal(f.length, 4);
  assert.match(f[0], /dart:core-patch/);
  assert.match(f[1], /package:app\/features\/chat\/foo\.dart/);
});

test("fingerprint: kotlin frames keep com.sparky.app and drop line numbers and lambda ids", () => {
  const a = "java.lang.IllegalStateException: boom\n\tat com.sparky.app.Updater.install(Updater.kt:88)\n\tat com.sparky.app.MainActivity$onCreate$1.invoke(MainActivity.kt:30)";
  const b = a.replace("Updater.kt:88", "Updater.kt:91").replace("$onCreate$1", "$onCreate$2");
  assert.equal(fingerprintOf("kotlin", "IllegalStateException", a), fingerprintOf("kotlin", "IllegalStateException", b));
});

test("fingerprint: obfuscated frames use their virtual offset, not the run-specific absolute address", () => {
  const t = (abs: string) => `*** *** ***\nbuild_id: 'abc'\n#00 abs ${abs} virt 00000000002fe2c0 _kDartIsolateSnapshotInstructions+0x2b2c0\n#01 abs ${abs} virt 0000000000300aa0 _kDartIsolateSnapshotInstructions+0x2caa0`;
  assert.equal(fingerprintOf("dart", "Error", t("000000750000a000")), fingerprintOf("dart", "Error", t("000000760000b000")));
  assert.notEqual(fingerprintOf("dart", "Error", t("000000750000a000")), fingerprintOf("dart", "Error", t("000000750000a000").replace("2fe2c0", "2fe2c4")));
});

test("fingerprint: with no frames the message digits are normalized", () => {
  assert.equal(fingerprintOf("anr", "ANR", "", "Input dispatching timed out after 5001 ms"), fingerprintOf("anr", "ANR", "", "Input dispatching timed out after 5230 ms"));
  assert.notEqual(fingerprintOf("anr", "ANR", "", "Input dispatching timed out"), fingerprintOf("anr", "ANR", "", "Broadcast of Intent timed out"));
});

// ---- pure: scrubbing and validation --------------------------------------------------

const item = (over: Partial<ErrorItem> = {}): ErrorItem =>
  errorsBody.parse({ errors: [{ kind: "dart", type: "StateError", message: "boom", stack: DART_A, build: 30, ...over }] }).errors[0];

test("scrub: emails, phone numbers and keys are redacted from messages and breadcrumbs", () => {
  const e = prepareError(
    item({
      message: "Failed for alice@example.com phone +91 98765 43210 key sk-abcdefghijklmnopqrstuvwxyz123456",
      breadcrumbs: [{ c: "route", m: "opened bob@example.org" }],
    }),
  );
  const all = JSON.stringify(e);
  assert.ok(!all.includes("alice@example.com") && !all.includes("bob@example.org") && !all.includes("98765 43210"));
  assert.ok(!all.includes("sk-abcdefghijklmnopqrstuvwxyz123456"));
});

test("scrub: message 200 chars, stack 8 KB, breadcrumbs last 30 of 80 chars, device whitelisted", () => {
  const e = prepareError(
    item({
      message: "x".repeat(5000),
      stack: "#0 a (package:app/a.dart:1:1)\n".repeat(2000),
      breadcrumbs: Array.from({ length: 45 }, (_, i) => ({ t: i, c: "route", m: "m".repeat(300) })),
      device: { model: "Pixel", sdk: 34, evil: "x", userEmail: "a@b.co" } as ErrorItem["device"],
    }),
  );
  assert.ok(e.message.length <= 200);
  assert.ok(e.stack.length <= 8 * 1024);
  assert.equal(e.breadcrumbs.length, 30);
  assert.equal(e.breadcrumbs[0].t, 15);
  assert.ok(e.breadcrumbs.every((b) => b.m.length <= 80));
  assert.deepEqual(Object.keys(e.device).sort(), ["model", "sdk"]);
});

test("scrub: stack redaction keeps long hex addresses intact so traces still symbolize", () => {
  const stack = "#00 abs 0000007b5c0a3b2c virt 00000000002fe2c0 _kDartIsolateSnapshotInstructions+0x2b2c0\nreported by carol@example.com";
  const s = scrubStack(stack);
  assert.ok(s.includes("abs 0000007b5c0a3b2c virt 00000000002fe2c0"));
  assert.ok(!s.includes("carol@example.com"));
  assert.equal(scrubText("", 10), "");
});

test("scrub: fingerprint is computed before redaction", () => {
  const a = prepareError(item({ message: "user a@example.com failed" }));
  const b = prepareError(item({ message: "user b@example.com failed" }));
  assert.equal(a.fingerprint, b.fingerprint);
});

test("validation: batch limits, kinds and ids", () => {
  const one = { kind: "dart", build: 1 };
  assert.ok(errorsBody.safeParse({ errors: Array.from({ length: 10 }, () => one) }).success);
  assert.ok(!errorsBody.safeParse({ errors: Array.from({ length: 11 }, () => one) }).success);
  assert.ok(!errorsBody.safeParse({ errors: [] }).success);
  assert.ok(!errorsBody.safeParse({ errors: [{ kind: "weird", build: 1 }] }).success);
  assert.ok(!sessionsBody.safeParse({ sessions: [{ id: "nope", build: 1, startedAt: 1 }] }).success);
});

test("prepare: client timestamps outside a week or in the future use the server clock", () => {
  const now = Date.now();
  assert.equal(prepareError(item({ at: now - 3600_000 }), now).at.getTime(), now - 3600_000);
  assert.equal(prepareError(item({ at: now + 3600_000 }), now).at.getTime(), now);
  assert.equal(prepareError(item({ at: now - 30 * 86_400_000 }), now).at.getTime(), now);
});

// ---- pure: decisions and math --------------------------------------------------------

test("samples: at most 5 per group per build and 200 per user per day", () => {
  assert.equal(shouldStoreSample(SAMPLES_PER_BUILD - 1, 0), true);
  assert.equal(shouldStoreSample(SAMPLES_PER_BUILD, 0), false);
  assert.equal(shouldStoreSample(0, USER_DAILY_SAMPLE_CAP - 1), true);
  assert.equal(shouldStoreSample(0, USER_DAILY_SAMPLE_CAP), false);
});

test("crash-free math", () => {
  assert.equal(crashFreeRate(0, 0), null);
  assert.equal(crashFreeRate(100, 0), 1);
  assert.equal(crashFreeRate(200, 3), 0.985);
  assert.equal(crashFreeRate(3, 9), 0);
});

test("regression: a resolved group reopens only on a newer build; ignored stays ignored", () => {
  assert.equal(statusAfterHit("resolved", 31, 30), "open");
  assert.equal(statusAfterHit("resolved", 30, 30), "resolved");
  assert.equal(statusAfterHit("ignored", 31, 30), "ignored");
});

test("session outcome keeps the first known value; crash may replace killed", () => {
  assert.equal(mergeOutcome("unknown", "ok"), "ok");
  assert.equal(mergeOutcome("ok", "crash"), "ok");
  assert.equal(mergeOutcome("killed", "anr"), "anr");
});

test("retention cutoffs", () => {
  const now = Date.UTC(2026, 9, 21);
  assert.equal(retentionCutoff(now, 30).toISOString(), "2026-09-21T00:00:00.000Z");
  assert.equal(retentionCutoff(now, 90).toISOString(), "2026-07-23T00:00:00.000Z");
});

// ---- http: gating and rate limits (no database needed: these fail before any query) ---

async function serve(user: { id: string | null; role: "owner" | "user" } | null) {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    if (user) req.user = { id: user.id, role: user.role, sid: null, bypass: false };
    next();
  });
  app.use("/app", appRouter);
  app.use("/admin/errors", adminErrorsRouter);
  app.use("/admin/health", adminHealthRouter);
  app.use(errorMiddleware);
  const server = await new Promise<import("node:http").Server>((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  return { base, close: () => new Promise((r) => server.close(r)) };
}
const post = (base: string, path: string, body: unknown) =>
  fetch(`${base}${path}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });

test("http: owner-only routes answer 403 to a normal user and 401-class errors to nobody", async () => {
  const user = await serve({ id: randomUUID(), role: "user" });
  try {
    for (const [method, path] of [
      ["GET", "/admin/errors"],
      ["GET", `/admin/errors/${"a".repeat(40)}`],
      ["PATCH", `/admin/errors/${"a".repeat(40)}`],
      ["GET", "/admin/health/builds"],
      ["GET", "/admin/errors/events/1/user"],
    ]) {
      const r = await fetch(`${user.base}${path}`, { method, headers: { "content-type": "application/json" }, body: method === "PATCH" ? "{}" : undefined });
      assert.equal(r.status, 403, `${method} ${path}`);
    }
  } finally {
    await user.close();
  }
  const anon = await serve(null);
  try {
    assert.equal((await post(anon.base, "/app/errors", { errors: [{ kind: "dart", build: 1 }] })).status, 401);
    assert.equal((await fetch(`${anon.base}/admin/errors`)).status, 403);
  } finally {
    await anon.close();
  }
});

test("http: ingest rejects malformed batches before touching the database", async () => {
  const s = await serve({ id: randomUUID(), role: "user" });
  try {
    assert.equal((await post(s.base, "/app/errors", { errors: [] })).status, 400);
    assert.equal((await post(s.base, "/app/errors", { errors: Array.from({ length: 11 }, () => ({ kind: "dart", build: 1 })) })).status, 400);
    assert.equal((await post(s.base, "/app/sessions", { sessions: [{ id: "x", build: 1, startedAt: 1 }] })).status, 400);
  } finally {
    await s.close();
  }
});

test("http: /app/errors is rate limited per user (21st request in a minute gets 429)", async () => {
  const s = await serve({ id: randomUUID(), role: "user" });
  const other = await serve({ id: randomUUID(), role: "user" });
  try {
    let last = 0;
    for (let i = 0; i < 21; i++) last = (await post(s.base, "/app/errors", { errors: [] })).status;
    assert.equal(last, 429);
    // The limiter is per user: another account is unaffected.
    assert.equal((await post(other.base, "/app/errors", { errors: [] })).status, 400);
  } finally {
    await s.close();
    await other.close();
  }
});

// ---- database ------------------------------------------------------------------------

const dbReady = await new Promise<boolean>((resolve) => {
  if (!config.databaseUrl) return resolve(false);
  const timer = setTimeout(() => resolve(false), 8000);
  onDbUp(() => {
    clearTimeout(timer);
    resolve(true);
  });
  initDb();
});
const migrated =
  dbReady &&
  (await db()
    .$queryRaw<Array<{ n: number }>>`SELECT count(*)::int AS n FROM information_schema.tables WHERE table_name = 'app_error_events'`
    .then((r) => r[0].n > 0)
    .catch(() => false));
after(() => closeDb());
const needsDb = { skip: migrated ? false : "database not reachable or migration 20261021100000 not applied" };

const tempUser = async () => (await db().user.create({ data: { email: `err-test-${randomUUID()}@example.test` } })).id;
/** A unique stack per test so groups never collide across runs. */
const uniqueStack = () => `#0 T.run (package:app/test/${randomUUID()}.dart:1:1)\n#1 T.go (package:app/test/go.dart:2:2)`;

test("db: group upsert counts every hit, distinct users once, and caps samples per build", needsDb, async () => {
  const [u1, u2] = [await tempUser(), await tempUser()];
  const stack = uniqueStack();
  const mk = (build: number): ErrorItem => item({ stack, build, type: "StateError", message: "boom" });
  const fp = prepareError(mk(30)).fingerprint;
  try {
    for (let i = 0; i < 7; i++) await ingestErrors(u1, [mk(30)]);
    const r = await ingestErrors(u2, [mk(30), mk(31)]);
    assert.equal(r.accepted, 2);
    const d = await groupDetail(fp);
    assert.equal(d.group.count, 9);
    assert.equal(d.group.users, 2);
    assert.equal(d.group.firstBuild, 30);
    assert.equal(d.group.lastBuild, 31);
    const b30 = d.builds.find((b) => b.build === 30)!;
    assert.equal(b30.count, 8);
    assert.equal(b30.users, 2);
    assert.equal(d.builds.find((b) => b.build === 31)!.count, 1);
    // 5 samples for build 30, 1 for build 31; the user is shown by id prefix only.
    assert.equal(d.samples.filter((s) => s.build === 30).length, SAMPLES_PER_BUILD);
    assert.equal(d.samples.filter((s) => s.build === 31).length, 1);
    assert.ok(d.samples.every((s) => s.user.length === 8));
    // Listing for a build sorts by users affected on that build.
    const list = await listGroups({ build: 30, status: "open", limit: 200 });
    assert.equal(list.groups.find((g) => g.fingerprint === fp)!.buildUsers, 2);
  } finally {
    await db().appErrorGroup.deleteMany({ where: { fingerprint: fp } });
    await db().user.deleteMany({ where: { id: { in: [u1, u2] } } });
  }
});

test("db: resolve, reopen on a newer build, ignore", needsDb, async () => {
  const u = await tempUser();
  const stack = uniqueStack();
  const mk = (build: number) => item({ stack, build });
  const fp = prepareError(mk(30)).fingerprint;
  try {
    await ingestErrors(u, [mk(30)]);
    await setGroupStatus(fp, "resolved");
    await ingestErrors(u, [mk(30)]);
    assert.equal((await groupDetail(fp)).group.status, "resolved");
    await ingestErrors(u, [mk(31)]);
    assert.equal((await groupDetail(fp)).group.status, "open");
    await setGroupStatus(fp, "ignored");
    await ingestErrors(u, [mk(32)]);
    assert.equal((await groupDetail(fp)).group.status, "ignored");
    await assert.rejects(() => setGroupStatus("0".repeat(40), "resolved"), /Unknown/);
  } finally {
    await db().appErrorGroup.deleteMany({ where: { fingerprint: fp } });
    await db().user.deleteMany({ where: { id: u } });
  }
});

test("db: stored rows contain no PII and the user comes from the caller, not the payload", needsDb, async () => {
  const u = await tempUser();
  const stack = uniqueStack();
  const e = item({ stack, message: "bad input from dave@example.com", breadcrumbs: [{ c: "route", m: "dave@example.com" }] });
  const fp = prepareError(e).fingerprint;
  try {
    await ingestErrors(u, [{ ...e, userId: randomUUID() } as ErrorItem]);
    const rows = await db().appErrorEvent.findMany({ where: { fingerprint: fp } });
    assert.equal(rows.length, 1);
    assert.equal(rows[0].userId, u);
    assert.ok(!JSON.stringify({ ...rows[0], id: String(rows[0].id) }).includes("dave@example.com"));
  } finally {
    await db().appErrorGroup.deleteMany({ where: { fingerprint: fp } });
    await db().user.deleteMany({ where: { id: u } });
  }
});

test("db: sessions upsert, belong to their creator, and crash-free is computed per build", needsDb, async () => {
  const [u1, u2] = [await tempUser(), await tempUser()];
  const build = 900_000_000 + Math.floor(Math.random() * 1000);
  const old = Date.now() - 3600_000;
  const ids = Array.from({ length: 4 }, () => randomUUID());
  try {
    await ingestSessions(u1, ids.map((id, i) => ({ id, build, startedAt: old + i, outcome: "unknown" as const })));
    await ingestSessions(u1, [
      { id: ids[0], build, startedAt: old, endedAt: old + 1000, outcome: "ok" },
      { id: ids[1], build, startedAt: old, outcome: "crash" },
      { id: ids[2], build, startedAt: old, outcome: "anr" },
      { id: ids[3], build, startedAt: old, endedAt: old + 5, outcome: "ok" },
    ]);
    // Another user cannot rewrite u1's session.
    assert.equal(await ingestSessions(u2, [{ id: ids[0], build, startedAt: old, outcome: "crash" }]), 0);
    // A session that started a minute ago may still be running and is not counted yet.
    await ingestSessions(u2, [{ id: randomUUID(), build, startedAt: Date.now() - 60_000, outcome: "unknown" }]);
    const h = (await buildsHealth(7)).find((b) => b.build === build)!;
    assert.equal(h.sessions, 4);
    assert.equal(h.crashed, 2);
    assert.equal(h.crashFree, 0.5);
    assert.equal(h.users, 1);
    const row = await db().appSession.findUnique({ where: { id: ids[0] } });
    assert.equal(row!.outcome, "ok");
    // A later "ok" cannot erase a recorded crash.
    await ingestSessions(u1, [{ id: ids[1], build, startedAt: old, endedAt: old + 9, outcome: "ok" }]);
    assert.equal((await db().appSession.findUnique({ where: { id: ids[1] } }))!.outcome, "crash");
  } finally {
    await db().appSession.deleteMany({ where: { build } });
    await db().user.deleteMany({ where: { id: { in: [u1, u2] } } });
  }
});

test("db: retention sweeps events after 30 days and sessions after 90, keeping group counts", needsDb, async () => {
  const u = await tempUser();
  const stack = uniqueStack();
  const fp = prepareError(item({ stack })).fingerprint;
  const sOld = randomUUID();
  const sNew = randomUUID();
  try {
    await ingestErrors(u, [item({ stack })]);
    await db().$executeRaw`UPDATE app_error_events SET at = now() - interval '31 days' WHERE fingerprint = ${fp}`;
    await ingestErrors(u, [item({ stack })]);
    await ingestSessions(u, [
      { id: sOld, build: 1, startedAt: Date.now() - 91 * 86_400_000, outcome: "ok" },
      { id: sNew, build: 1, startedAt: Date.now() - 80 * 86_400_000, outcome: "ok" },
    ]);
    const r = await sweepAppErrors();
    assert.ok(r.events >= 1 && r.sessions >= 1);
    const d = await groupDetail(fp);
    assert.equal(d.samples.length, 1);
    assert.equal(d.group.count, 2);
    assert.equal(await db().appSession.findUnique({ where: { id: sOld } }), null);
    assert.ok(await db().appSession.findUnique({ where: { id: sNew } }));
  } finally {
    await db().appErrorGroup.deleteMany({ where: { fingerprint: fp } });
    await db().appSession.deleteMany({ where: { id: { in: [sOld, sNew] } } });
    await db().user.deleteMany({ where: { id: u } });
  }
});

test("db: owner endpoints list groups and crash-free per build over http", needsDb, async () => {
  const u = await tempUser();
  const stack = uniqueStack();
  const e = item({ stack, build: 44 });
  const fp = prepareError(e).fingerprint;
  const owner = await serve({ id: u, role: "owner" });
  try {
    await ingestErrors(u, [e]);
    const list = (await (await fetch(`${owner.base}/admin/errors?build=44`)).json()) as { groups: Array<{ fingerprint: string }> };
    assert.ok(list.groups.some((g) => g.fingerprint === fp));
    const detail = await fetch(`${owner.base}/admin/errors/${fp}`);
    assert.equal(detail.status, 200);
    const patch = await fetch(`${owner.base}/admin/errors/${fp}`, { method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify({ status: "resolved" }) });
    assert.equal(patch.status, 200);
    assert.equal((await fetch(`${owner.base}/admin/errors/${"b".repeat(40)}`)).status, 404);
    const builds = (await (await fetch(`${owner.base}/admin/health/builds`)).json()) as { builds: unknown[] };
    assert.ok(Array.isArray(builds.builds));
  } finally {
    await owner.close();
    await db().appErrorGroup.deleteMany({ where: { fingerprint: fp } });
    await db().user.deleteMany({ where: { id: u } });
  }
});
