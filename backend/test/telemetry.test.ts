import { after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { config } from "../src/config.js";
import { closeDb, initDb, onDbUp, tx, type Tx } from "../src/db/prisma.js";
import { errorCodeFor, scrub } from "../src/db/usage.js";
import { bucketFor, events, overview, timeseries } from "../src/telemetry/queries.js";

// ---- pure helpers ---------------------------------------------------------------

test("bucketFor: defaults per window and never exceeds the point cap", () => {
  assert.equal(bucketFor("1h"), "1m");
  assert.equal(bucketFor("24h"), "5m");
  assert.equal(bucketFor("24h", "1m"), "1m"); // 1440 points: allowed
  assert.equal(bucketFor("7d", "1m"), "1h"); // 10080 / 2016 points: too many
  assert.equal(bucketFor("30d", "5m"), "1h");
});

test("scrub: keys and long tokens never reach the table", () => {
  const fake = ["gsk", "abcdefghijklmnop1234"].join("_");
  const out = scrub(`401 Unauthorized: invalid api_key=${fake} Bearer abc.def`)!;
  assert.ok(!out.includes(fake));
  assert.ok(!out.includes("abc.def"));
  assert.ok(scrub("x".repeat(400))!.length <= 300);
  assert.equal(scrub(""), null);
});

test("errorCodeFor: http status first, then message shape", () => {
  assert.equal(errorCodeFor(429, "too many"), "http_429");
  assert.equal(errorCodeFor(undefined, "no first byte within 20000ms"), "timeout");
  assert.equal(errorCodeFor(0, "empty response"), "empty");
  assert.equal(errorCodeFor(undefined, "fetch failed"), "network");
});

// ---- aggregations against the database (rolled back) --------------------------------

const dbReady = await new Promise<boolean>((resolve) => {
  if (!config.databaseUrl) return resolve(false);
  const timer = setTimeout(() => resolve(false), 8000);
  onDbUp(() => {
    clearTimeout(timer);
    resolve(true);
  });
  initDb();
});
after(() => closeDb());
const needsDb = { skip: dbReady ? false : "database not reachable" };

const ROLLBACK = new Error("rollback");
async function rolledBack(fn: (c: Tx) => Promise<void>): Promise<void> {
  try {
    await tx(async (c) => {
      await fn(c);
      throw ROLLBACK;
    });
  } catch (e) {
    if (e !== ROLLBACK) throw e;
  }
}

/** Seeds rows under a unique provider so real rows never interfere. */
async function seed(c: Tx, provider: string) {
  const user = await c.user.create({ data: { email: `telemetry-${provider}@example.test`, name: "T" }, select: { id: true } });
  const ago = (min: number) => new Date(Date.now() - min * 60_000);
  const rows = [
    // model a: 3 ok, 1 failed 429; latencies 100/200/300/400
    { ts: ago(2), model: "a", purpose: "chat", ok: true, status: 200, latencyMs: 100, ttftMs: 50, promptTokens: 10, completionTokens: 5 },
    { ts: ago(2), model: "a", purpose: "chat", ok: true, status: 200, latencyMs: 200, ttftMs: 70, promptTokens: 20, completionTokens: 5 },
    { ts: ago(5), model: "a", purpose: "title", ok: true, status: 200, latencyMs: 300, ttftMs: 90, promptTokens: 30, completionTokens: 5 },
    { ts: ago(5), model: "a", purpose: "title", ok: false, status: 429, errorCode: "http_429", errorMessage: "rate limited", latencyMs: 400 },
    // model b: 1 failed timeout, 1 legacy row with the provider prefix in the model column
    { ts: ago(30), model: "b", purpose: "table-draft", ok: false, errorCode: "timeout", errorMessage: "timeout", latencyMs: 1000 },
    { ts: ago(31), model: `${provider}:b`, purpose: null, ok: true, status: 200, latencyMs: 500, promptTokens: 1, completionTokens: 1 },
    // outside the 1h window
    { ts: ago(90), model: "a", purpose: "chat", ok: true, status: 200, latencyMs: 10, promptTokens: 1000, completionTokens: 1000 },
  ];
  await c.usageEvent.createMany({ data: rows.map((r) => ({ provider, kind: "chat", userId: user.id, ...r })) });
  return user.id;
}

test("overview: totals, per model, per kind, per user and top errors", needsDb, async () => {
  await rolledBack(async (c) => {
    const provider = `t-${randomUUID().slice(0, 8)}`;
    const userId = await seed(c, provider);
    const o = await overview(c, "1h", { provider });

    assert.equal(o.totals.requests, 6);
    assert.equal(o.totals.failed, 2);
    assert.equal(o.totals.ok, 4);
    assert.equal(o.totals.failureRate, 0.3333);
    assert.equal(o.totals.tokensIn, 61);
    assert.equal(o.totals.tokensOut, 16);
    assert.equal(o.totals.latencyP50, 350); // of 100,200,300,400,500,1000
    assert.equal(o.totals.ttftP50, 70);

    const a = o.models.find((m) => m.model === "a")!;
    assert.equal(a.requests, 4);
    assert.equal(a.failed, 1);
    assert.deepEqual(a.failuresByCode, { http_429: 1 });
    assert.equal(a.lastError?.code, "http_429");
    assert.equal(a.lastError?.kind, "title");
    assert.equal(a.latencyP50, 250);
    // The legacy "provider:b" row is folded into "b".
    const b = o.models.find((m) => m.model === "b")!;
    assert.equal(b.requests, 2);
    assert.equal(o.models.length, 2);

    const kinds = Object.fromEntries(o.kinds.map((k) => [k.kind, k.requests]));
    assert.deepEqual(kinds, { chat: 3, title: 2, "table-draft": 1 });

    assert.equal(o.users.length, 1);
    assert.equal(o.users[0].userId, userId);
    assert.equal(o.users[0].window.requests, 6);
    assert.ok(o.users[0].today.requests >= 6);

    assert.equal(o.topErrors.length, 2);
    assert.equal(o.providers.length, 1);

    // Filters narrow everything.
    const onlyB = await overview(c, "1h", { provider, model: "b" });
    assert.equal(onlyB.totals.requests, 2);
    const titles = await overview(c, "1h", { provider, kind: "title" });
    assert.equal(titles.totals.requests, 2);
    const day = await overview(c, "24h", { provider });
    assert.equal(day.totals.requests, 7);
  });
});

test("timeseries: gap-filled minute buckets with the right counts", needsDb, async () => {
  await rolledBack(async (c) => {
    const provider = `t-${randomUUID().slice(0, 8)}`;
    await seed(c, provider);
    const s = await timeseries(c, "1h", "1m", { provider });
    assert.equal(s.bucket, "1m");
    assert.ok(s.points.length >= 60 && s.points.length <= 62, `points ${s.points.length}`);
    assert.equal(s.points.reduce((n, p) => n + p.requests, 0), 6);
    assert.equal(s.points.reduce((n, p) => n + p.failed, 0), 2);
    assert.equal(s.points.reduce((n, p) => n + p.tokensIn, 0), 61);
    // Buckets are one minute apart and ascending.
    const gaps = new Set(s.points.slice(1).map((p, i) => Date.parse(p.t) - Date.parse(s.points[i].t)));
    assert.deepEqual([...gaps], [60_000]);
    const hourly = await timeseries(c, "24h", "1h", { provider, ok: false });
    assert.equal(hourly.points.reduce((n, p) => n + p.requests, 0), 2);
  });
});

test("events: newest first, cursor paging and filters", needsDb, async () => {
  await rolledBack(async (c) => {
    const provider = `t-${randomUUID().slice(0, 8)}`;
    await seed(c, provider);
    const first = await events(c, 4, null, { provider });
    assert.equal(first.events.length, 4);
    assert.ok(first.nextBefore);
    const ids = first.events.map((e) => BigInt(e.id));
    assert.deepEqual(ids, [...ids].sort((x, y) => (x > y ? -1 : 1)));
    const rest = await events(c, 4, BigInt(first.nextBefore!), { provider });
    assert.equal(rest.events.length, 3);
    assert.equal(rest.nextBefore, null);
    const failed = await events(c, 50, null, { provider, ok: false });
    assert.equal(failed.events.length, 2);
    assert.ok(failed.events.every((e) => !e.ok && e.errorCode));
    assert.ok(failed.events[0].userEmail?.startsWith("telemetry-"));
    const legacy = await events(c, 50, null, { provider, model: "b" });
    assert.equal(legacy.events.length, 2);
    assert.ok(legacy.events.every((e) => e.model === "b"));
  });
});

test("overview: legacy rows without status or error are unknown, turn rows are summarised apart", needsDb, async () => {
  await rolledBack(async (c) => {
    const provider = `t-${randomUUID().slice(0, 8)}`;
    const ts = new Date(Date.now() - 60_000);
    // Same statement as migration 20261013100000 (rolled back with the rest), for databases that predate it.
    await c.$executeRawUnsafe(`ALTER TABLE usage_events DROP CONSTRAINT IF EXISTS usage_events_kind_check`);
    await c.$executeRawUnsafe(`ALTER TABLE usage_events ADD CONSTRAINT usage_events_kind_check CHECK (kind IN ('chat','embed','search','fetch','transcribe','github','turn'))`);
    await c.usageEvent.createMany({
      data: [
        { provider, kind: "chat", model: "a", ok: true, status: 200, ts },
        { provider, kind: "chat", model: "a", ok: false, status: 503, ts },
        { provider, kind: "chat", model: "a", ok: false, errorCode: "timeout", ts },
        { provider, kind: "chat", model: "a", ok: false, ts }, // legacy: neither status nor error
        { provider, kind: "turn", model: "turn", purpose: "turn-summary", ok: true, count: 4, ttftMs: 800, latencyMs: 3000, ts },
        { provider, kind: "turn", model: "turn", purpose: "turn-summary", ok: true, count: 2, ttftMs: 400, latencyMs: 2000, ts },
      ],
    });
    const o = await overview(c, "1h", { provider });
    assert.equal(o.totals.requests, 4);
    assert.equal(o.totals.failed, 2);
    assert.equal(o.totals.unknown, 1);
    assert.equal(o.totals.ok, 1);
    assert.equal(o.providers[0].spark.length, 24);
    assert.equal(o.providers[0].spark.reduce((s, x) => s + x, 0), 4);
    assert.equal(o.turns?.turns, 2);
    assert.equal(o.turns?.auxAvg, 3);
    assert.equal(o.turns?.ttftAvg, 600);
    const failed = await events(c, 50, null, { provider, ok: false });
    assert.equal(failed.events.length, 2);
  });
});
