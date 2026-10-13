import { after, test } from "node:test";
import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import type { AddressInfo } from "node:net";
import express from "express";
import { config } from "../src/config.js";
import { closeDb, db, initDb, onDbUp } from "../src/db/prisma.js";
import { isSealedObject, resetMasterKeysForTests, setKeyStore, userCrypto } from "../src/crypto/userData.js";
import { io, putUserObject } from "../src/storage/s3.js";
import { blobRouter } from "../src/routes/blob.js";
import { blobUrl } from "../src/files/blobUrl.js";
import { conversationsRouter } from "../src/routes/conversations.js";
import { errorMiddleware } from "../src/util/errors.js";
import { createMemory, listMemories, similarMemories, slotMemories, updateMemory } from "../src/memory/store.js";
import { prismaStore } from "../src/docs/store.js";
import { storeDoc } from "../src/ingest/queue.js";
import { searchConversations } from "../src/conversations/search.js";

// Repository-level tests: real rows in a migrated database (skipped when none is reachable or the
// 20261020100000_user_data_encryption migration is not applied there).
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
    .$queryRaw<Array<{ n: number }>>`SELECT count(*)::int AS n FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'data_key_enc'`
    .then((r) => r[0].n > 0)
    .catch(() => false));
after(() => closeDb());
const needsDb = { skip: migrated ? false : "database not reachable or migration 20261020100000 not applied" };

config.dataKey = randomBytes(32).toString("base64");
resetMasterKeysForTests();
setKeyStore(null);

const axis = (i: number) => Array.from({ length: 1024 }, (_, k) => (k === i ? 1 : 0));
const tempUser = async () => (await db().user.create({ data: { email: `enc-test-${randomUUID()}@example.test`, chatRecallEnabled: false } })).id;

/** The conversations router behind a fake sign-in, on an ephemeral port. */
async function serve(userId: string) {
  const app = express();
  app.use(express.json({ limit: "4mb" }));
  app.use((req, _res, next) => {
    req.user = { id: userId, role: "user", sid: null, bypass: false };
    next();
  });
  app.use("/conversations", conversationsRouter);
  app.use(errorMiddleware);
  const server = await new Promise<import("node:http").Server>((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  return { base, close: () => new Promise((r) => server.close(r)) };
}

test("db: chats are stored sealed, read back plain, listed, searched and forked", needsDb, async () => {
  const userId = await tempUser();
  const api = await serve(userId);
  try {
    const id = randomUUID();
    const secret = "my passport number is X1234567 and rust async runtimes";
    const put = await fetch(`${api.base}/conversations/${id}`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        messages: [
          { role: "user", content: `Rust async runtimes compared. ${secret}`, citations: [], evidence: [] },
          { role: "assistant", content: "Tokio is the common choice for async runtimes.", evidence: [{ tag: "W1", claim: "tokio", quote: "most used", score: 0.5 }], meta: { note: "private meta" } },
        ],
      }),
    });
    assert.equal(put.status, 200);
    const summary = (await put.json()) as { title: string; preview: string };
    assert.equal(summary.preview.startsWith("Rust async runtimes compared"), true);
    assert.ok(summary.title && !summary.title.startsWith("enc:v1:"));

    // What the database holds is ciphertext.
    const conv = await db().conversation.findUnique({ where: { id } });
    assert.ok(conv!.title!.startsWith("enc:v1:") && conv!.preview!.startsWith("enc:v1:"));
    const rows = await db().$queryRaw<Array<{ content: string; evidence: unknown; meta: unknown }>>`SELECT content, evidence, meta FROM conversation_messages WHERE conversation_id = ${id}::uuid ORDER BY position`;
    for (const r of rows) assert.ok(r.content.startsWith("enc:v1:"));
    const raw = JSON.stringify(rows) + JSON.stringify(conv);
    for (const s of ["passport", "Tokio", "most used", "private meta", "Rust async"]) assert.ok(!raw.includes(s), `plaintext leaked: ${s}`);

    // Reads decrypt transparently.
    const got = (await (await fetch(`${api.base}/conversations/${id}`)).json()) as { messages: Array<{ content: string; evidence: unknown[]; meta: Record<string, unknown> }> };
    assert.ok(got.messages[0].content.includes("X1234567"));
    assert.equal(got.messages[1].evidence.length, 1);
    assert.equal(got.messages[1].meta.note, "private meta");

    // Listing and search work on decrypted text.
    const list = (await (await fetch(`${api.base}/conversations`)).json()) as { conversations: Array<{ id: string; title: string }> };
    assert.equal(list.conversations[0].id, id);
    assert.ok(!list.conversations[0].title.startsWith("enc:v1:"));
    const found = (await (await fetch(`${api.base}/conversations?q=${encodeURIComponent("async runtime")}`)).json()) as { conversations: Array<{ id: string; snippet: string | null }> };
    assert.equal(found.conversations.length, 1);
    assert.equal(found.conversations[0].id, id);
    assert.ok(found.conversations[0].snippet?.toLowerCase().includes("async"));
    const none = (await (await fetch(`${api.base}/conversations?q=zebra`)).json()) as { conversations: unknown[] };
    assert.equal(none.conversations.length, 0);
    // A different user never sees these chats in search.
    const other = await tempUser();
    assert.deepEqual(await searchConversations({ uid: other, q: "async", archived: false, before: null, limit: 10, crypto: await userCrypto(other) }), []);

    // Fork copies the sealed rows; the fork reads back plain and its title is sealed too.
    const fork = await fetch(`${api.base}/conversations/${id}/fork`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ at: 2 }) });
    assert.equal(fork.status, 201);
    const forked = (await fork.json()) as { id: string; title: string; messages: Array<{ content: string }> };
    assert.ok(forked.title.endsWith("· fork"));
    assert.ok(forked.messages[0].content.includes("X1234567"));
    const forkRow = await db().conversation.findUnique({ where: { id: forked.id }, select: { title: true } });
    assert.ok(forkRow!.title!.startsWith("enc:v1:"));

    // Renaming seals the new title.
    const patched = await fetch(`${api.base}/conversations/${id}`, { method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify({ title: "Visa paperwork" }) });
    assert.equal(((await patched.json()) as { title: string }).title, "Visa paperwork");
    assert.ok((await db().conversation.findUnique({ where: { id }, select: { title: true } }))!.title!.startsWith("enc:v1:"));
  } finally {
    await api.close();
  }
});

test("db: a legacy plaintext chat still reads and searches", needsDb, async () => {
  const userId = await tempUser();
  const id = randomUUID();
  await db().conversation.create({ data: { id, userId, title: "Old plaintext chat about kubernetes", preview: "k8s", messageCount: 1, messages: { create: { position: 0, role: "user", content: "How do I debug a CrashLoopBackOff pod?" } } } });
  const api = await serve(userId);
  try {
    const got = (await (await fetch(`${api.base}/conversations/${id}`)).json()) as { title: string; messages: Array<{ content: string }> };
    assert.equal(got.title, "Old plaintext chat about kubernetes");
    assert.equal(got.messages[0].content, "How do I debug a CrashLoopBackOff pod?");
    const found = (await (await fetch(`${api.base}/conversations?q=crashloopbackoff`)).json()) as { conversations: Array<{ id: string }> };
    assert.equal(found.conversations[0]?.id, id);
  } finally {
    await api.close();
  }
});

test("db: memory text and slot are sealed; list search, slot lookup and similarity still work", needsDb, async () => {
  const userId = await tempUser();
  const m = await createMemory(userId, { text: "Uses Neovim for everything.", kind: "preference", slot: "tool:neovim", vec: axis(3) });
  assert.equal(m.text, "Uses Neovim for everything.");
  assert.equal(m.slot, "tool:neovim");

  const raw = await db().$queryRaw<Array<{ text: string; slot: string; slot_enc: string }>>`SELECT text, slot, slot_enc FROM memories WHERE id = ${m.id}::uuid`;
  assert.ok(raw[0].text.startsWith("enc:v1:") && raw[0].slot_enc.startsWith("enc:v1:"));
  assert.match(raw[0].slot, /^h1:/);
  assert.ok(!JSON.stringify(raw).includes("Neovim") && !JSON.stringify(raw).includes("neovim"));

  assert.equal((await listMemories(userId)).items[0].text, "Uses Neovim for everything.");
  assert.equal((await listMemories(userId, { q: "NEOVIM" })).total, 1); // decrypt-and-filter
  assert.equal((await listMemories(userId, { q: "emacs" })).total, 0);
  assert.deepEqual((await slotMemories(userId, ["tool:neovim"])).map((x) => [x.text, x.slot]), [["Uses Neovim for everything.", "tool:neovim"]]);
  const near = await similarMemories(userId, axis(3), 3);
  assert.equal(near[0].text, "Uses Neovim for everything.");
  assert.equal(near[0].slot, "tool:neovim");

  // One memory per slot still holds (the blind index collides): the second write drops its slot instead of failing.
  const dup = await createMemory(userId, { text: "Uses Neovim daily.", kind: "preference", slot: "tool:neovim", vec: null });
  assert.equal(dup.slot, null);

  const upd = await updateMemory(userId, m.id, { text: "Uses Helix now.", slot: "tool:helix" }, null);
  assert.equal(upd?.text, "Uses Helix now.");
  assert.equal(upd?.slot, "tool:helix");
  // Another user's data key cannot read it, and the user scoping still applies.
  assert.equal((await listMemories(await tempUser())).total, 0);
});

test("db: DOC mode content is sealed in every table and reads back", needsDb, async () => {
  const userId = await tempUser();
  const doc = await prismaStore.create({ userId, conversationId: null, prompt: "write about my secret startup idea", options: { length: "short", profile: { signature: "Nikhil K" } } as never, title: "Startup memo" });
  await prismaStore.update(userId, doc.id, { summary: "A summary of the secret idea", glossary: [{ term: "moat", definition: "defensibility" }] as never });
  await prismaStore.setSections(userId, doc.id, [
    { sectionId: "s1", ord: 0, heading: "Intro", level: 2, markdown: "Our secret sauce is X.", summary: "intro", status: "done", sourceIds: [], usedIds: [], evidence: [], images: [], model: null, words: 5, updatedAt: new Date().toISOString() },
  ]);
  await prismaStore.addRevision(userId, doc.id, "s1", 1, "Older secret sauce text", "edit");
  await prismaStore.addHighlight(userId, doc.id, { sectionId: "s1", quote: "secret sauce", prefix: "Our ", suffix: " is X", color: "yellow", note: "check this" });

  const raw = JSON.stringify(
    await db().$queryRaw`SELECT d.title, d.prompt, d.summary, d.glossary, d.options, s.heading, s.markdown, r.markdown AS rev, h.quote, h.note
      FROM docs d JOIN doc_sections s ON s.doc_id = d.id JOIN doc_revisions r ON r.doc_id = d.id JOIN doc_highlights h ON h.doc_id = d.id WHERE d.id = ${doc.id}::uuid`,
  );
  for (const s of ["Startup memo", "secret startup", "secret idea", "moat", "Nikhil", "Intro", "secret sauce", "check this"]) assert.ok(!raw.includes(s), `plaintext leaked: ${s}`);
  assert.ok(raw.includes('"length":"short"') || raw.includes("short")); // plain settings stay readable

  const back = await prismaStore.get(userId, doc.id);
  assert.equal(back?.title, "Startup memo");
  assert.equal(back?.prompt, "write about my secret startup idea");
  assert.equal(back?.summary, "A summary of the secret idea");
  assert.equal(back?.sections[0].markdown, "Our secret sauce is X.");
  assert.equal((back?.options as { profile: { signature: string } }).profile.signature, "Nikhil K");
  assert.equal((await prismaStore.revisions(userId, doc.id, "s1"))[0].markdown, "Older secret sauce text");
  const marks = await prismaStore.highlights(userId, doc.id);
  assert.equal(marks[0].quote, "secret sauce");
  assert.equal(marks[0].note, "check this");
  assert.equal((await prismaStore.list(userId))[0].title, "Startup memo");
});

test("db: knowledge-base chunks are sealed; keyword search over the stripped tsv still works", needsDb, async () => {
  const userId = await tempUser();
  const c = await userCrypto(userId);
  const source = await db().source.create({ data: { type: "web", uri: `https://example.test/${randomUUID()}`, userId, status: "ready" } });
  const content = "Kubernetes operators reconcile desired state with observed state.";
  await storeDoc(
    source.id,
    {
      doc: { url: `${source.uri}/page`, title: "Operators", markdown: content },
      hash: c.blindIndex("documents", "content_hash", "h"),
      chunks: [{ ord: 0, headingPath: "Intro > Operators", content, tokenCount: 12, hash: c.blindIndex("chunks", "content_hash", "ch") }],
      reuse: new Map(),
      need: [0],
    },
    c,
    false,
    () => `[${axis(7).join(",")}]`,
  );
  const rows = await db().$queryRaw<Array<{ content: string; heading_path: string; tsv: string; hit: boolean }>>`
    SELECT content, heading_path, tsv::text AS tsv, tsv @@ websearch_to_tsquery('english', 'kubernetes or reconciling') AS hit FROM chunks WHERE source_id = ${source.id}::uuid`;
  assert.equal(rows.length, 1);
  assert.ok(rows[0].content.startsWith("enc:v1:") && rows[0].heading_path.startsWith("enc:v1:"));
  assert.ok(!rows[0].content.includes("Kubernetes"));
  assert.equal(rows[0].hit, true); // stemmed keyword search works on the lexeme column
  assert.ok(!/:\d/.test(rows[0].tsv), "positions are stripped");
  assert.equal(c.open("chunks", "content", rows[0].content), content);
});

test("db: file links serve decrypted bytes (ranges too), legacy plaintext objects, and refuse bad signatures", needsDb, async () => {
  const userId = await tempUser();
  const store = new Map<string, Buffer>();
  const real = { put: io.put, get: io.get };
  io.put = async (k, b) => void store.set(k, b);
  io.get = async (k) => store.get(k) ?? Promise.reject(new Error("NoSuchKey"));
  const app = express();
  app.use("/files/blob", blobRouter);
  app.use(errorMiddleware);
  const server = await new Promise<import("node:http").Server>((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  try {
    const bytes = randomBytes(1000);
    const id = randomUUID();
    const key = `${id}/original.png`;
    await putUserObject(userId, key, bytes, "image/png");
    assert.ok(isSealedObject(store.get(key)!));
    await db().storedFile.create({ data: { id, userId, name: "a.png", mime: "image/png", size: bytes.length, kind: "image", status: "ready", s3Key: key } });
    const legacyId = randomUUID();
    store.set(`${legacyId}/original.txt`, Buffer.from("legacy plaintext body"));
    await db().storedFile.create({ data: { id: legacyId, userId, name: "n.html", mime: "text/html", size: 21, kind: "document", status: "ready", s3Key: `${legacyId}/original.txt` } });

    const local = (u: string) => u.replace(config.publicBaseUrl, `http://127.0.0.1:${(server.address() as AddressInfo).port}`);
    const res = await fetch(local(blobUrl(id, "original")));
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("content-type"), "image/png");
    assert.deepEqual(Buffer.from(await res.arrayBuffer()), bytes);
    const part = await fetch(local(blobUrl(id, "original")), { headers: { range: "bytes=10-19" } });
    assert.equal(part.status, 206);
    assert.equal(part.headers.get("content-range"), "bytes 10-19/1000");
    assert.deepEqual(Buffer.from(await part.arrayBuffer()), bytes.subarray(10, 20));

    const legacy = await fetch(local(blobUrl(legacyId, "original")));
    assert.equal(await legacy.text(), "legacy plaintext body");
    assert.match(legacy.headers.get("content-disposition") ?? "", /^attachment/); // an uploaded page never renders on the API origin
    assert.match(legacy.headers.get("content-security-policy") ?? "", /sandbox/);

    assert.equal((await fetch(local(blobUrl(id, "original")).replace(/sig=[0-9a-f]/, "sig=0"))).status, 404);
    assert.equal((await fetch(local(blobUrl(id, "original", Date.now() - 2 * 3600_000)))).status, 404);
    assert.equal((await fetch(local(blobUrl(id, "thumb")))).status, 404); // no thumbnail stored
  } finally {
    io.put = real.put;
    io.get = real.get;
    await new Promise((r) => server.close(r));
  }
});
