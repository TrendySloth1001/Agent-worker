import { test, after } from "node:test";
import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import type { AddressInfo } from "node:net";
import express from "express";
import { config } from "../src/config.js";
import { closeDb, db, initDb, onDbUp } from "../src/db/prisma.js";
import { resetMasterKeysForTests, setKeyStore, userCrypto } from "../src/crypto/userData.js";
import { runAs } from "../src/auth/context.js";
import { withFreshUrls } from "../src/files/attachmentUrls.js";
import { blobUrl } from "../src/files/blobUrl.js";
import { signedInfo, type FileRow } from "../src/files/store.js";
import { insightIo, parseImageInsight, parseSummary, summaryInput, videoSource, type InsightDeps } from "../src/files/insight.js";
import { baseEvidence } from "../src/files/video.js";
import { filesRouter } from "../src/routes/files.js";
import { conversationsRouter } from "../src/routes/conversations.js";
import { errorMiddleware } from "../src/util/errors.js";

const ID = "0f8fad5b-d9cb-469f-a165-70867728950e";
const S3_LINK = "https://bucket.s3.amazonaws.com/0f8fad5b/original.jpg?X-Amz-Signature=abc&X-Amz-Expires=3600";

// ---- no client-facing storage links ------------------------------------------------------------------------

test("withFreshUrls replaces stored storage links and stale signatures with fresh blob links", () => {
  const [a, b, c, d] = withFreshUrls([
    { id: ID, name: "a.jpg", kind: "image", url: S3_LINK, thumbUrl: S3_LINK },
    { id: ID.toUpperCase(), name: "b.pdf", kind: "document", url: "https://sparky.cloudnsofts.com/files/blob/x/original?exp=1&sig=00" },
    { id: ID, name: "gone.png", kind: "image", status: "deleted", deleted: true, url: S3_LINK },
    { id: "not-a-uuid", name: "x", kind: "image", url: S3_LINK },
  ]);
  assert.match(String(a.url), /\/files\/blob\/[0-9a-f-]+\/original\?exp=\d+&sig=[0-9a-f]{64}$/);
  assert.match(String(a.thumbUrl), /\/files\/blob\/[0-9a-f-]+\/thumb\?exp=/);
  assert.ok(!JSON.stringify([a, b, c, d]).includes("amazonaws") && !JSON.stringify([a, b, c, d]).includes("X-Amz"));
  assert.match(String(b.url), /\/files\/blob\/0f8fad5b-d9cb-469f-a165-70867728950e\/original/);
  assert.equal(b.thumbUrl, undefined); // a document never had a poster
  assert.equal(c.url, undefined);
  assert.equal(d.url, undefined);
  assert.deepEqual(withFreshUrls(null), []);
});

test("signedInfo hands out API blob links only", async () => {
  const row = { id: ID, conversationId: null, name: "a.jpg", mime: "image/jpeg", size: 10, kind: "image", status: "ready", error: null, s3Key: `${ID}/original.jpg`, thumbKey: `${ID}/thumb.jpg`, meta: {}, createdAt: new Date() } as FileRow;
  const info = await signedInfo(row);
  for (const u of [info.url, info.thumbUrl]) assert.ok(u!.startsWith(`${config.publicBaseUrl}/files/blob/${ID}/`), u!);
  assert.ok(!JSON.stringify(info).includes("X-Amz"));
});

test("only the app-release flow may sign storage links (everything else must go through /files/blob)", () => {
  const offenders: string[] = [];
  const walk = (dir: string) => {
    for (const name of readdirSync(dir)) {
      const p = path.join(dir, name);
      if (statSync(p).isDirectory()) {
        if (name !== "generated") walk(p);
      } else if (p.endsWith(".ts") && /\bpresign\(|getSignedUrl\(/.test(readFileSync(p, "utf8"))) offenders.push(path.relative("src", p));
    }
  };
  walk("src");
  assert.deepEqual(offenders.sort(), ["ota/service.ts", "storage/s3.ts"]);
});

// ---- parsing and prompts -------------------------------------------------------------------------------------

test("parseSummary: JSON, JSON in prose, plain prose, empty", () => {
  assert.deepEqual(parseSummary('{"summary":"A lease.","keyPoints":["Rent 500","  ", "Ends May"]}'), { summary: "A lease.", keyPoints: ["Rent 500", "Ends May"] });
  assert.equal(parseSummary('<think>hmm</think>Sure! {"summary":"Short","keyPoints":[]} done')?.summary, "Short");
  assert.deepEqual(parseSummary("Just prose."), { summary: "Just prose.", keyPoints: [] });
  assert.equal(parseSummary('{"summary":"","keyPoints":["x"]}'), null);
  assert.equal(parseSummary("  "), null);
});

test("parseImageInsight keeps the caption and the text read from the picture", () => {
  const r = parseImageInsight('{"caption":"A receipt on a table.","text":"TOTAL 12.40","keyPoints":["cafe"]}');
  assert.deepEqual(r, { caption: "A receipt on a table.", ocr: "TOTAL 12.40", keyPoints: ["cafe"] });
  assert.equal(parseImageInsight('{"caption":"","text":""}'), null);
});

test("summaryInput keeps the head and tail of a long text", () => {
  assert.equal(summaryInput("short", 100), "short");
  const long = "a".repeat(5000) + "MIDDLE" + "z".repeat(5000);
  const cut = summaryInput(long, 1000);
  assert.ok(cut.length < 1100 && cut.startsWith("aaa") && cut.endsWith("zzz") && !cut.includes("MIDDLE"));
});

test("videoSource lists described frames with times, then the transcript", () => {
  const ev = baseEvidence({ durationS: 75, hasAudio: true, frameTimes: [0, 30], hasTranscript: true });
  ev.frames[1].caption = "A dog runs.";
  const s = videoSource(ev, "hello there");
  assert.match(s, /\[0?0:30\] A dog runs\./);
  assert.match(s, /What is said:\nhello there/);
});

// ---- routes (real rows; skipped without a migrated database) --------------------------------------------------

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

config.dataKey = randomBytes(32).toString("base64");
resetMasterKeysForTests();
setKeyStore(null);

const tempUser = async () => (await db().user.create({ data: { email: `preview-test-${randomUUID()}@example.test`, chatRecallEnabled: false } })).id;

async function serve(userId: string) {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    const user = { id: userId, role: "user" as const, sid: null, bypass: false };
    req.user = user;
    runAs(user, next);
  });
  app.use("/files", filesRouter);
  app.use("/conversations", conversationsRouter);
  app.use(errorMiddleware);
  const server = await new Promise<import("node:http").Server>((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  return { base: `http://127.0.0.1:${(server.address() as AddressInfo).port}`, close: () => new Promise((r) => server.close(r)) };
}

function fakeDeps(calls: { chat: number; vision: number }): InsightDeps {
  return {
    chat: async () => {
      calls.chat++;
      return '{"summary":"A lease for a flat in Pune.","keyPoints":["Rent is 500","Ends in May"]}';
    },
    vision: async () => {
      calls.vision++;
      return '{"caption":"A receipt on a table.","text":"TOTAL 12.40","keyPoints":["cafe"]}';
    },
    image: async () => "AAAA",
    video: { frame: async () => "AAAA", describe: async () => '["a","b"]', save: async () => {} },
    now: () => new Date("2026-10-15T00:00:00Z"),
  };
}

async function putFile(userId: string, over: Record<string, unknown>) {
  const id = randomUUID();
  const text = typeof over.text === "string" ? (await userCrypto(userId)).seal("files", "text", over.text) : null;
  await db().storedFile.create({
    data: { id, userId, name: "lease.pdf", mime: "application/pdf", size: 100, kind: "document", status: "ready", s3Key: `${id}/original.pdf`, ...over, text },
  });
  return id;
}

test("db: GET /files/:id/text pages by offset and refuses other users' files", needsDb, async () => {
  const owner = await tempUser();
  const other = await tempUser();
  const id = await putFile(owner, { text: "0123456789".repeat(10) });
  const mine = await serve(owner);
  const theirs = await serve(other);
  try {
    const first = (await (await fetch(`${mine.base}/files/${id}/text?limit=30`)).json()) as { text: string; offset: number; truncated: boolean; chars: number };
    assert.deepEqual([first.text.length, first.offset, first.truncated, first.chars], [30, 0, true, 100]);
    const last = (await (await fetch(`${mine.base}/files/${id}/text?limit=30&offset=90`)).json()) as typeof first;
    assert.deepEqual([last.text, last.offset, last.truncated], ["0123456789", 90, false]);
    assert.equal((await fetch(`${theirs.base}/files/${id}/text`)).status, 404);
    assert.equal((await fetch(`${theirs.base}/files/${id}/insight`)).status, 404);
    assert.equal((await fetch(`${theirs.base}/files/${id}/insight`, { method: "POST" })).status, 404);
  } finally {
    await mine.close();
    await theirs.close();
  }
});

test("db: insight is generated once, cached sealed on the file record, and read back without a model call", needsDb, async () => {
  const owner = await tempUser();
  const id = await putFile(owner, { text: "Lease agreement. Rent is 500 per month. Ends in May." });
  const calls = { chat: 0, vision: 0 };
  const real = insightIo.deps;
  insightIo.deps = fakeDeps(calls);
  const api = await serve(owner);
  try {
    const before = (await (await fetch(`${api.base}/files/${id}/insight`)).json()) as { insight: unknown; hasText: boolean; chars: number };
    assert.equal(before.insight, null);
    assert.equal(before.hasText, true);
    assert.equal(calls.chat, 0, "reading never calls a model");

    const post = await fetch(`${api.base}/files/${id}/insight`, { method: "POST", headers: { "content-type": "application/json" }, body: "{}" });
    assert.equal(post.status, 200);
    const made = (await post.json()) as { insight: { summary: string; keyPoints: string[] } };
    assert.equal(made.insight.summary, "A lease for a flat in Pune.");
    assert.deepEqual(made.insight.keyPoints, ["Rent is 500", "Ends in May"]);

    await fetch(`${api.base}/files/${id}/insight`, { method: "POST" });
    assert.equal(calls.chat, 1, "second request is served from the cache");
    const again = (await (await fetch(`${api.base}/files/${id}/insight`)).json()) as typeof made;
    assert.equal(again.insight.summary, made.insight.summary);
    await fetch(`${api.base}/files/${id}/insight`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ force: true }) });
    assert.equal(calls.chat, 2);

    // At rest: sealed, no plaintext, and never part of the public file info.
    const [row] = await db().$queryRaw<Array<{ insight: string }>>`SELECT meta->>'insight' AS insight FROM files WHERE id = ${id}::uuid`;
    assert.ok(row.insight.startsWith("enc:v1:"));
    assert.ok(!row.insight.includes("Pune") && !row.insight.includes("Rent"));
    const info = JSON.stringify(await (await fetch(`${api.base}/files/${id}`)).json());
    assert.ok(!info.includes("Pune") && !info.includes("enc:v1:"));
  } finally {
    insightIo.deps = real;
    await api.close();
  }
});

test("db: images get a caption and the text read from them; files still being read answer 409", needsDb, async () => {
  const owner = await tempUser();
  const img = await putFile(owner, { name: "r.jpg", mime: "image/jpeg", kind: "image", s3Key: "x/r.jpg" });
  const busy = await putFile(owner, { status: "processing" });
  const empty = await putFile(owner, { name: "scan.pdf" });
  const calls = { chat: 0, vision: 0 };
  const real = insightIo.deps;
  insightIo.deps = fakeDeps(calls);
  const api = await serve(owner);
  try {
    const r = (await (await fetch(`${api.base}/files/${img}/insight`, { method: "POST" })).json()) as { insight: { caption: string; ocr: string } };
    assert.equal(r.insight.caption, "A receipt on a table.");
    assert.equal(r.insight.ocr, "TOTAL 12.40");
    assert.equal(calls.vision, 1);
    assert.equal((await fetch(`${api.base}/files/${busy}/insight`, { method: "POST" })).status, 409);
    assert.equal((await fetch(`${api.base}/files/${empty}/insight`, { method: "POST" })).status, 404);
    assert.equal(calls.chat, 0);
  } finally {
    insightIo.deps = real;
    await api.close();
  }
});

test("db: a saved chat's attachments come back with fresh blob links, never the stored ones", needsDb, async () => {
  const owner = await tempUser();
  const fileId = await putFile(owner, {});
  const api = await serve(owner);
  try {
    const chat = randomUUID();
    const put = await fetch(`${api.base}/conversations/${chat}`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ messages: [{ role: "user", content: "see file", attachments: [{ id: fileId, name: "lease.pdf", kind: "document", mime: "application/pdf", url: S3_LINK }] }] }),
    });
    assert.equal(put.status, 200);
    // A row saved by an older server still holds the link it was sent with.
    await db().$executeRaw`UPDATE conversation_messages SET attachments = jsonb_set(attachments, '{0,url}', to_jsonb(${S3_LINK}::text)) WHERE conversation_id = ${chat}::uuid`;
    const got = (await (await fetch(`${api.base}/conversations/${chat}`)).json()) as { messages: Array<{ attachments: Array<{ url: string }> }> };
    const url = got.messages[0].attachments[0].url;
    assert.ok(url.startsWith(`${config.publicBaseUrl}/files/blob/${fileId}/original?exp=`), url);
    assert.ok(!JSON.stringify(got).includes("amazonaws"));
    assert.equal(blobUrl(fileId, "original").split("?")[0], url.split("?")[0]);
  } finally {
    await api.close();
  }
});
