import { test } from "node:test";
import assert from "node:assert/strict";
import { cleanRename, decodeCursor, encodeCursor, parseListQuery, sortPlan } from "../src/files/library.js";
import { fitBitrate } from "../src/files/media.js";
import { knownKeys } from "../src/files/store.js";
import { AppError } from "../src/util/errors.js";

const ID = "0f8fad5b-d9cb-469f-a165-70867728950e";
const MiB = 1024 * 1024;

test("parseListQuery: defaults, plural kinds, clamped limit", () => {
  assert.deepEqual(parseListQuery({}), { kind: null, q: "", sort: "newest", cursor: null, limit: 40 });
  const q = parseListQuery({ kind: "Videos", q: "  trip  ", sort: "largest", limit: "500" });
  assert.equal(q.kind, "video");
  assert.equal(q.q, "trip");
  assert.equal(q.sort, "largest");
  assert.equal(q.limit, 100);
  assert.equal(parseListQuery({ kind: "all" }).kind, null);
  assert.equal(parseListQuery({ limit: "0" }).limit, 1);
});

test("parseListQuery: rejects unknown kind, sort and bad cursors", () => {
  assert.throws(() => parseListQuery({ kind: "spreadsheet" }), AppError);
  assert.throws(() => parseListQuery({ sort: "oldest" }), AppError);
  assert.throws(() => parseListQuery({ cursor: "nope" }), AppError);
  // A size cursor is not valid for a name sort and vice versa.
  assert.throws(() => parseListQuery({ sort: "name", cursor: encodeCursor({ v: 12, id: ID }) }), AppError);
  assert.throws(() => parseListQuery({ sort: "largest", cursor: encodeCursor({ v: "a", id: ID }) }), AppError);
});

test("cursor round trip", () => {
  const c = { v: "2026-10-11T18:32:40.000Z", id: ID };
  assert.deepEqual(decodeCursor(encodeCursor(c), "newest"), c);
  assert.deepEqual(parseListQuery({ sort: "largest", cursor: encodeCursor({ v: 42, id: ID }) }).cursor, { v: 42, id: ID });
});

test("sortPlan: keyset filters break ties on id", () => {
  assert.equal(sortPlan("newest", null).after, null);
  assert.deepEqual(sortPlan("largest", null).orderBy, [{ size: "desc" }, { id: "desc" }]);
  const largest = sortPlan("largest", { v: 10, id: ID }).after as { OR: unknown[] };
  assert.deepEqual(largest.OR, [{ size: { lt: 10n } }, { size: 10n, id: { lt: ID } }]);
  const name = sortPlan("name", { v: "b.pdf", id: ID }).after as { OR: unknown[] };
  assert.deepEqual(name.OR, [{ name: { gt: "b.pdf" } }, { name: "b.pdf", id: { gt: ID } }]);
  const newest = sortPlan("newest", { v: "2026-01-01T00:00:00.000Z", id: ID }).after as { OR: Array<{ createdAt: unknown }> };
  assert.deepEqual(newest.OR[0], { createdAt: { lt: new Date("2026-01-01T00:00:00.000Z") } });
});

test("cleanRename keeps the extension and strips paths", () => {
  assert.equal(cleanRename("holiday", "VID_001.mp4"), "holiday.mp4");
  assert.equal(cleanRename("holiday.MP4", "VID_001.mp4"), "holiday.MP4");
  assert.equal(cleanRename("../../etc/notes", "a.txt"), "notes.txt");
  assert.equal(cleanRename("x\u0000y", "README"), "xy");
  assert.equal(cleanRename("a".repeat(300), "f.pdf").length, 200);
  assert.ok(cleanRename("a".repeat(300), "f.pdf").endsWith(".pdf"));
  assert.throws(() => cleanRename("   ", "a.txt"), AppError);
  assert.throws(() => cleanRename(5, "a.txt"), AppError);
});

test("fitBitrate keeps a clip under the storage limit", () => {
  // One minute fits comfortably: capped at 4 Mbit/s.
  assert.equal(fitBitrate(60, 50 * MiB), 4000);
  // Ten minutes: ~640 kbit/s total, minus audio.
  const tenMin = fitBitrate(600, 50 * MiB)!;
  assert.ok(tenMin > 400 && tenMin < 600, String(tenMin));
  const bytes = ((tenMin + 96) * 1000 * 600) / 8;
  assert.ok(bytes < 50 * MiB);
  // Hours of video cannot fit at a watchable quality.
  assert.equal(fitBitrate(4 * 3600, 50 * MiB), null);
  assert.equal(fitBitrate(0, 50 * MiB), null);
});

test("knownKeys lists original, thumbnail and frames once", () => {
  const keys = knownKeys({ s3Key: `${ID}/original.mp4`, thumbKey: `${ID}/thumb.jpg`, meta: { frameKeys: [`${ID}/frame-0.jpg`, `${ID}/thumb.jpg`, 7] } });
  assert.deepEqual(keys, [`${ID}/original.mp4`, `${ID}/thumb.jpg`, `${ID}/frame-0.jpg`]);
  assert.deepEqual(knownKeys({ s3Key: "k", thumbKey: null, meta: {} }), ["k"]);
});
