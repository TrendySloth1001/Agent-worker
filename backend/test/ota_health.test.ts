import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { deflateRawSync } from "node:zlib";
import type { NextFunction, Request, Response } from "express";
import { eventsBody, installSuccessRate, MAX_AGE_MS, MAX_EVENTS, toRows } from "../src/ota/events.js";
import { apkVersionCode, ApkError, expectedVersionCode, parseManifest, readManifest } from "../src/ota/apk.js";
import { stageApk } from "../src/ota/upload.js";
import { putStream, type MultipartIo } from "../src/storage/s3.js";
import { rateLimit } from "../src/util/rateLimit.js";
import { AppError } from "../src/util/errors.js";

const ev = (over: Record<string, unknown> = {}) => ({ build: 33, toBuild: 34, stage: "download_ok", ...over });

// ---- events validation ----

test("eventsBody: accepts a valid batch and defaults via to full", () => {
  const r = eventsBody.parse({ deviceId: "abcd1234-ef56", events: [ev(), ev({ stage: "install_ok", via: "resume", bytes: 1234 })] });
  assert.equal(r.events.length, 2);
  assert.equal(r.events[0].via, "full");
  assert.equal(r.events[1].via, "resume");
});

test("eventsBody: rejects empty, oversized, unknown stage, bad code and bad device id", () => {
  assert.equal(eventsBody.safeParse({ events: [] }).success, false);
  assert.equal(eventsBody.safeParse({ events: Array.from({ length: MAX_EVENTS + 1 }, () => ev()) }).success, false);
  assert.equal(eventsBody.safeParse({ events: Array.from({ length: MAX_EVENTS }, () => ev()) }).success, true);
  assert.equal(eventsBody.safeParse({ events: [ev({ stage: "exploded" })] }).success, false);
  assert.equal(eventsBody.safeParse({ events: [ev({ code: "bad code!" })] }).success, false);
  assert.equal(eventsBody.safeParse({ events: [ev({ code: "x".repeat(41) })] }).success, false);
  assert.equal(eventsBody.safeParse({ deviceId: "short", events: [ev()] }).success, false);
  assert.equal(eventsBody.safeParse({ events: [ev({ via: "carrier-pigeon" })] }).success, false);
  assert.equal(eventsBody.safeParse({ events: [ev({ build: -1 })] }).success, false);
});

test("toRows: user comes from the session, a userId in the body is ignored", () => {
  const body = eventsBody.parse({ userId: "someone-else", events: [{ ...ev(), userId: "someone-else" }] });
  const rows = toRows(body, "session-user");
  assert.equal(rows.length, 1);
  assert.equal(rows[0].userId, "session-user");
  assert.equal(JSON.stringify(rows, (_k, v) => (typeof v === "bigint" ? v.toString() : v)).includes("someone-else"), false);
});

test("toRows: ok is derived from the stage, not trusted from the client", () => {
  const body = eventsBody.parse({ events: [ev({ stage: "install_fail" }), ev({ stage: "install_ok" }), ev({ stage: "signature_mismatch" }), ev({ stage: "cancelled" }), ev({ stage: "first_launch_ok" })] });
  assert.deepEqual(
    toRows(body, "u").map((r) => r.ok),
    [false, true, false, true, true],
  );
});

test("toRows: future and ancient timestamps are clamped to now", () => {
  const now = new Date("2026-10-14T12:00:00Z");
  const body = eventsBody.parse({
    events: [ev({ at: now.getTime() + 3_600_000 }), ev({ at: now.getTime() - MAX_AGE_MS - 1 }), ev({ at: now.getTime() - 1000 }), ev()],
  });
  const at = toRows(body, "u", now).map((r) => r.at.getTime());
  assert.equal(at[0], now.getTime());
  assert.equal(at[1], now.getTime());
  assert.equal(at[2], now.getTime() - 1000);
  assert.equal(at[3], now.getTime());
});

test("installSuccessRate: cancelled excluded, null with no attempts", () => {
  assert.equal(installSuccessRate([]), null);
  assert.equal(installSuccessRate([{ stage: "cancelled", count: 9 }]), null);
  assert.equal(
    installSuccessRate([
      { stage: "install_ok", count: 8 },
      { stage: "install_fail", count: 1 },
      { stage: "verify_fail", count: 1 },
      { stage: "cancelled", count: 5 },
    ]),
    0.8,
  );
});

// ---- rate limit (the limiter the route mounts) ----

test("health events rate limit: per user, the 11th request in a minute gets 429", () => {
  const limit = rateLimit(10, 60_000, "auto", { name: "health-events-test" });
  const req = (id: string) => ({ user: { id, role: "user", sid: null, bypass: false }, headers: {}, path: "/health/events" }) as unknown as Request;
  const res = { setHeader() {} } as unknown as Response;
  const run = (id: string) => {
    let err: unknown;
    limit(req(id), res, ((e?: unknown) => (err = e)) as NextFunction);
    return err;
  };
  for (let i = 0; i < 10; i++) assert.equal(run("a"), undefined);
  const refused = run("a") as AppError;
  assert.equal(refused.status, 429);
  assert.equal(run("b"), undefined); // another user has their own budget
});

// ---- APK parsing ----

const fixture = readFileSync(new URL("./fixtures/AndroidManifest.v34.xml", import.meta.url));

/** A minimal zip with one deflated entry AndroidManifest.xml (plus a filler entry before it). */
function zipWith(manifest: Buffer, method: 0 | 8 = 8): Buffer {
  const entries = [
    { name: "classes.dex", data: Buffer.from("dex-data"), method: 0 as const },
    { name: "AndroidManifest.xml", data: manifest, method },
  ];
  const locals: Buffer[] = [];
  const centrals: Buffer[] = [];
  let off = 0;
  for (const e of entries) {
    const stored = e.method === 8 ? deflateRawSync(e.data) : e.data;
    const name = Buffer.from(e.name);
    const lh = Buffer.alloc(30);
    lh.writeUInt32LE(0x04034b50, 0);
    lh.writeUInt16LE(e.method, 8);
    lh.writeUInt32LE(stored.length, 18);
    lh.writeUInt32LE(e.data.length, 22);
    lh.writeUInt16LE(name.length, 26);
    const local = Buffer.concat([lh, name, stored]);
    const ch = Buffer.alloc(46);
    ch.writeUInt32LE(0x02014b50, 0);
    ch.writeUInt16LE(e.method, 10);
    ch.writeUInt32LE(stored.length, 20);
    ch.writeUInt32LE(e.data.length, 24);
    ch.writeUInt16LE(name.length, 28);
    ch.writeUInt32LE(off, 42);
    centrals.push(Buffer.concat([ch, name]));
    locals.push(local);
    off += local.length;
  }
  const cd = Buffer.concat(centrals);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(cd.length, 12);
  eocd.writeUInt32LE(off, 16);
  return Buffer.concat([...locals, cd, eocd]);
}
const reader = (b: Buffer) => async (o: number, l: number) => b.subarray(o, o + l);

test("parseManifest: reads versionCode and package from a real AndroidManifest.xml", () => {
  const m = parseManifest(fixture);
  assert.equal(m.versionCode, 2034);
  assert.equal(m.packageName, "com.sparky.app");
});

test("apkVersionCode: deflated and stored manifests in a zip", async () => {
  for (const method of [8, 0] as const) {
    const z = zipWith(fixture, method);
    assert.equal(await apkVersionCode(z.length, reader(z)), 2034);
  }
  assert.equal(expectedVersionCode(34), 2034);
});

test("readManifest: rejects non-zip and zip without a manifest", async () => {
  const junk = Buffer.alloc(100, 7);
  await assert.rejects(readManifest(junk.length, reader(junk)), ApkError);
  await assert.rejects(readManifest(5, reader(Buffer.alloc(5))), ApkError);
  await assert.rejects(async () => parseManifest(Buffer.from("not xml at all")), ApkError);
});

// ---- streaming upload ----

function fakeIo() {
  const calls: string[] = [];
  const partSizes: number[] = [];
  const bodies: Buffer[] = [];
  const io: MultipartIo = {
    async create() {
      calls.push("create");
      return "up1";
    },
    async part(_k, _id, n, body) {
      calls.push(`part${n}`);
      partSizes.push(body.length);
      bodies.push(Buffer.from(body));
      return `etag${n}`;
    },
    async complete(_k, _id, parts) {
      calls.push(`complete:${parts.length}`);
    },
    async abort() {
      calls.push("abort");
    },
    async put(_k, b) {
      calls.push("put");
      bodies.push(b);
    },
  };
  return { io, calls, partSizes, bodies };
}

async function* chunks(buf: Buffer, size: number) {
  for (let i = 0; i < buf.length; i += size) yield buf.subarray(i, i + size);
}

const fakeApk = (len: number) => {
  const b = Buffer.alloc(len, 0x61);
  b[0] = 0x50;
  b[1] = 0x4b;
  return b;
};

test("stageApk: streams in parts, sha256 and size match the bytes", async () => {
  const data = fakeApk(2500);
  const f = fakeIo();
  const r = await stageApk(chunks(data, 300), "releases/_incoming/x.apk", { io: f.io, partBytes: 1000 });
  assert.equal(r.size, 2500);
  assert.equal(r.sha256, createHash("sha256").update(data).digest("hex"));
  assert.deepEqual(f.partSizes, [1000, 1000, 500]);
  assert.deepEqual(f.calls, ["create", "part1", "part2", "part3", "complete:3"]);
  assert.ok(Buffer.concat(f.bodies).equals(data));
});

test("stageApk: a body under one part is a single PUT", async () => {
  const data = fakeApk(400);
  const f = fakeIo();
  const r = await stageApk(chunks(data, 100), "k", { io: f.io, partBytes: 1000 });
  assert.equal(r.size, 400);
  assert.deepEqual(f.calls, ["put"]);
});

test("stageApk: rejects a non-zip file and aborts the multipart upload", async () => {
  const data = Buffer.alloc(3000, 0x41);
  const f = fakeIo();
  await assert.rejects(stageApk(chunks(data, 500), "k", { io: f.io, partBytes: 1000 }), (e: unknown) => e instanceof AppError && e.status === 400);
  assert.ok(!f.calls.includes("complete:3"));
  assert.ok(!f.calls.includes("put"));
});

test("stageApk: enforces the size cap mid-stream and aborts an open multipart upload", async () => {
  const data = fakeApk(5000);
  const f = fakeIo();
  await assert.rejects(stageApk(chunks(data, 400), "k", { io: f.io, partBytes: 1000, maxBytes: 2500 }), (e: unknown) => e instanceof AppError && e.status === 413);
  assert.ok(f.calls.includes("abort"));
  assert.ok(!f.calls.some((c) => c.startsWith("complete")));
});

test("stageApk: an empty upload is a 400", async () => {
  const f = fakeIo();
  await assert.rejects(stageApk(chunks(Buffer.alloc(0), 10), "k", { io: f.io }), (e: unknown) => e instanceof AppError && e.status === 400);
});

test("putStream: a failing part upload aborts and rethrows", async () => {
  const f = fakeIo();
  f.io.part = async () => {
    throw new Error("s3 down");
  };
  await assert.rejects(putStream("k", chunks(fakeApk(3000), 1000), "x", { io: f.io, partBytes: 1000 }), /s3 down/);
  assert.ok(f.calls.includes("abort"));
});
