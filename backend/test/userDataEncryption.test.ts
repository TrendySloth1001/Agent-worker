import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { config } from "../src/config.js";
import {
  SEALED_PREFIX,
  currentMasterKeyId,
  isSealed,
  isSealedObject,
  openFor,
  resetMasterKeysForTests,
  rewrapDataKey,
  sealFor,
  setKeyStore,
  unwrapDataKey,
  userCrypto,
  wrapDataKey,
  wrappedKeyId,
  type KeyStore,
} from "../src/crypto/userData.js";
import { io, getUserObject, putUserObject } from "../src/storage/s3.js";
import { MSG, openConversationText, openMessage, sealConversation, sealMessage } from "../src/conversations/codec.js";
import { matchChat, queryMatcher } from "../src/conversations/search.js";
import { blobUrl, verifyBlob } from "../src/files/blobUrl.js";
import { conversationPatch, keyHash, memoryPatch, messagePatch, parseArgs, sealJsonValue } from "../src/scripts/encryptBackfill.js";
import { storedKey } from "../src/web/cacheStore.js";
import { scrub } from "../src/db/usage.js";
import { corsOptions } from "../src/util/security.js";

const b64 = () => randomBytes(32).toString("base64");

/** In-memory data-key store: stands in for users.data_key_enc. */
function memoryKeys(): KeyStore & { rows: Map<string, string> } {
  const rows = new Map<string, string>();
  return {
    rows,
    read: async (id) => rows.get(id) ?? null,
    writeIfAbsent: async (id, w) => (rows.has(id) ? false : (rows.set(id, w), true)),
    overwrite: async (id, w) => void rows.set(id, w),
  };
}

let keys: ReturnType<typeof memoryKeys>;
beforeEach(() => {
  config.dataKey = b64();
  config.dataKeyPrevious = undefined;
  resetMasterKeysForTests();
  keys = memoryKeys();
  setKeyStore(keys);
});

test("seal/open round-trip, random IVs, empty text stays empty", async () => {
  const u = randomUUID();
  const sealed = await sealFor(u, "memories", "text", "Lives in Pune, allergic to peanuts. ünïcode ✓");
  assert.ok(sealed.startsWith(SEALED_PREFIX));
  assert.ok(!sealed.includes("Pune"));
  assert.equal(await openFor(u, "memories", "text", sealed), "Lives in Pune, allergic to peanuts. ünïcode ✓");
  assert.notEqual(await sealFor(u, "memories", "text", "same"), await sealFor(u, "memories", "text", "same"));
  assert.equal(await sealFor(u, "memories", "text", ""), "");
});

test("AAD binds table, column and user: moved ciphertext does not open", async () => {
  const [a, b] = [randomUUID(), randomUUID()];
  const sealed = await sealFor(a, "conversation_messages", "content", "secret plan");
  await assert.rejects(openFor(a, "conversation_messages", "meta", sealed), /couldn't be read|decrypt_failed/);
  await assert.rejects(openFor(a, "memories", "content", sealed), /couldn't be read|decrypt_failed/);
  await assert.rejects(openFor(b, "conversation_messages", "content", sealed), /couldn't be read|decrypt_failed/);
  // Same user, same place: fine. Tampering is detected.
  assert.equal(await openFor(a, "conversation_messages", "content", sealed), "secret plan");
  const raw = Buffer.from(sealed.slice(SEALED_PREFIX.length), "base64");
  raw[raw.length - 1] ^= 1;
  await assert.rejects(openFor(a, "conversation_messages", "content", SEALED_PREFIX + raw.toString("base64")));
});

test("legacy plaintext passes through; plaintext that looks sealed is still protected", async () => {
  const u = randomUUID();
  assert.equal(await openFor(u, "memories", "text", "plain old memory"), "plain old memory");
  assert.equal(await openFor(null, "memories", "text", "unclaimed row"), "unclaimed row");
  assert.equal(await sealFor(null, "memories", "text", "unclaimed row"), "unclaimed row"); // no owner, no key
  const tricky = "enc:v1:not really encrypted";
  const sealed = await sealFor(u, "memories", "text", tricky);
  assert.equal(await openFor(u, "memories", "text", sealed), tricky);
});

test("each user has their own data key; one user's key cannot open another's data", async () => {
  const [a, b] = [randomUUID(), randomUUID()];
  const sa = await sealFor(a, "docs", "title", "A's title");
  await sealFor(b, "docs", "title", "B's title");
  assert.equal(keys.rows.size, 2);
  assert.notEqual(keys.rows.get(a), keys.rows.get(b));
  const ca = await userCrypto(a);
  const cb = await userCrypto(b);
  assert.throws(() => cb.open("docs", "title", sa));
  assert.equal(ca.open("docs", "title", sa), "A's title");
  // A wrapped key cannot be moved to another user either (AAD = user id).
  assert.throws(() => unwrapDataKey(b, keys.rows.get(a)!));
});

test("data key is created once, even when requests race", async () => {
  const u = randomUUID();
  const sealed = await Promise.all(Array.from({ length: 8 }, (_, i) => sealFor(u, "memories", "text", `m${i}`)));
  assert.equal(keys.rows.size, 1);
  const opened = await Promise.all(sealed.map((s) => openFor(u, "memories", "text", s)));
  assert.deepEqual(opened, Array.from({ length: 8 }, (_, i) => `m${i}`));
});

test("wrapped key format is rotation-ready: names its master key, re-wraps without changing the data", async () => {
  const u = randomUUID();
  const sealed = await sealFor(u, "memories", "text", "survives rotation");
  const oldKey = config.dataKey!;
  const oldId = currentMasterKeyId();
  const wrapped = keys.rows.get(u)!;
  assert.match(wrapped, /^wk:v1:[0-9a-f]{8}:/);
  assert.equal(wrappedKeyId(wrapped), oldId);

  // Rotate: new DATA_KEY, the old one kept only for unwrapping.
  config.dataKey = b64();
  config.dataKeyPrevious = oldKey;
  resetMasterKeysForTests();
  setKeyStore(keys);
  assert.notEqual(currentMasterKeyId(), oldId);
  assert.equal(await openFor(u, "memories", "text", sealed), "survives rotation"); // old wrapping still unwraps
  assert.equal(await rewrapDataKey(u), true);
  assert.equal(wrappedKeyId(keys.rows.get(u)!), currentMasterKeyId());
  assert.equal(await rewrapDataKey(u), false);

  // Old key dropped: re-wrapped data is still readable, un-rewrapped users would not be.
  config.dataKeyPrevious = undefined;
  resetMasterKeysForTests();
  setKeyStore(keys);
  assert.equal(await openFor(u, "memories", "text", sealed), "survives rotation");
  const other = randomUUID();
  keys.rows.set(other, wrapDataKey(other, randomBytes(32), { id: "deadbeef", key: randomBytes(32) }));
  await assert.rejects(userCrypto(other));
});

test("JSON columns: sealed as {$enc}, empty values left alone, legacy JSON passes through", async () => {
  const c = await userCrypto(randomUUID());
  const evidence = [{ tag: "K1", claim: "the sky is blue", quote: "blue", score: 0.9 }];
  const sealed = c.sealJson("conversation_messages", "evidence", evidence) as { $enc: string };
  assert.ok(isSealed(sealed.$enc));
  assert.ok(!JSON.stringify(sealed).includes("sky"));
  assert.deepEqual(c.openJson("conversation_messages", "evidence", sealed), evidence);
  assert.deepEqual(c.openJson("conversation_messages", "evidence", evidence), evidence);
  assert.deepEqual(c.sealJson("conversation_messages", "evidence", []), []);
  assert.deepEqual(c.sealJson("conversation_messages", "meta", {}), {});
});

test("messages: write -> stored ciphertext -> read, search still finds them", async () => {
  const u = randomUUID();
  const c = await userCrypto(u);
  const stored = sealMessage(c, {
    content: "How do rust async runtimes compare to goroutines?",
    citations: [{ id: "W1", title: "Tokio docs", snippet: "tokio is a runtime" }],
    images: [],
    evidence: [{ tag: "W1", claim: "tokio schedules tasks", quote: "work stealing", score: 0.8 }],
    meta: { doc: { id: "d1", title: "Private draft" } },
    table: { seats: [{ model: "x", text: "round table opinion" }], reviews: [], unresolved: [] },
  });
  const dump = JSON.stringify(stored);
  for (const secret of ["goroutines", "Tokio", "work stealing", "Private draft", "round table opinion"]) assert.ok(!dump.includes(secret), secret);
  assert.ok(isSealed(stored.content));
  const back = openMessage(c, stored);
  assert.equal(back.content, "How do rust async runtimes compare to goroutines?");
  assert.deepEqual(back.meta, { doc: { id: "d1", title: "Private draft" } });
  assert.deepEqual((back.table as { seats: unknown[] }).seats.length, 1);

  // Legacy plaintext rows read the same way.
  const legacy = openMessage(c, { content: "old plaintext", citations: [], images: [], evidence: [], meta: {}, table: null });
  assert.equal(legacy.content, "old plaintext");

  // Search over the decrypted view (what searchConversations does after loading and opening rows).
  const matcher = queryMatcher("async runtime");
  const hit = matchChat({ id: "c1", title: "Rust chat", messages: [{ role: "user", content: back.content }] }, "async runtime", matcher, false);
  assert.equal(hit?.id, "c1");
  assert.ok(hit?.snippet?.text.toLowerCase().includes("async"));
  assert.equal(matchChat({ id: "c2", title: "Cooking", messages: [{ role: "user", content: "pasta recipes" }] }, "async runtime", matcher, false), null);
  // Typo tolerance only in the fuzzy pass.
  const typo = queryMatcher("kubernetis");
  const chat = { id: "c3", title: "Infra", messages: [{ role: "assistant", content: "Deploy it on Kubernetes with Helm." }] };
  assert.equal(matchChat(chat, "kubernetis", typo, false), null);
  assert.equal(matchChat(chat, "kubernetis", typo, true)?.id, "c3");
  // Titles are searchable too; context messages never become the excerpt.
  const byTitle = matchChat({ id: "c4", title: "Quarterly budget", messages: [{ role: "context", content: "budget briefing" }] }, "budget", queryMatcher("budget"), false);
  assert.equal(byTitle?.snippet, null);
});

test("conversation text (title, preview, summary) is sealed and opens back", async () => {
  const c = await userCrypto(randomUUID());
  const row = sealConversation(c, { title: "Tax return 2026", preview: "help with my tax return", summary: null });
  assert.ok(isSealed(row.title!) && isSealed(row.preview!));
  assert.equal(row.summary, null);
  assert.deepEqual(openConversationText(c, row), { title: "Tax return 2026", preview: "help with my tax return", summary: null });
});

test("memory slot: blind index keeps lookups and uniqueness, the name is sealed", async () => {
  const c = await userCrypto(randomUUID());
  const other = await userCrypto(randomUUID());
  const a = c.blindIndex("memories", "slot", "tool:neovim");
  assert.equal(a, c.blindIndex("memories", "slot", "tool:neovim"));
  assert.notEqual(a, c.blindIndex("memories", "slot", "tool:vscode"));
  assert.notEqual(a, other.blindIndex("memories", "slot", "tool:neovim"));
  assert.ok(a.startsWith("h1:") && !a.includes("neovim"));
});

test("S3 bodies: encrypted before upload, decrypted on read, legacy plaintext objects still read", async () => {
  const store = new Map<string, Buffer>();
  const real = { put: io.put, get: io.get };
  io.put = async (k, b) => void store.set(k, b);
  io.get = async (k) => {
    const v = store.get(k);
    if (!v) throw new Error("NoSuchKey");
    return v;
  };
  try {
    const [a, b] = [randomUUID(), randomUUID()];
    const photo = randomBytes(4096);
    await putUserObject(a, "f1/original.jpg", photo, "image/jpeg");
    const stored = store.get("f1/original.jpg")!;
    assert.ok(isSealedObject(stored));
    assert.ok(!stored.includes(photo.subarray(0, 64)));
    assert.deepEqual(await getUserObject(a, "f1/original.jpg"), photo);
    // Legacy object: no marker, returned as is.
    store.set("old/original.pdf", Buffer.from("%PDF-1.7 plaintext"));
    assert.equal((await getUserObject(a, "old/original.pdf")).toString(), "%PDF-1.7 plaintext");
    // Another user, another key name, or no user: refused.
    await assert.rejects(getUserObject(b, "f1/original.jpg"));
    store.set("f2/original.jpg", stored);
    await assert.rejects(getUserObject(a, "f2/original.jpg"));
    await assert.rejects(getUserObject(null, "f1/original.jpg"));
  } finally {
    io.put = real.put;
    io.get = real.get;
  }
});

test("signed file links verify, expire and cannot be altered", () => {
  const id = randomUUID();
  const url = new URL(blobUrl(id, "original", 1_000_000));
  const exp = url.searchParams.get("exp");
  const sig = url.searchParams.get("sig");
  assert.ok(url.pathname.endsWith(`/files/blob/${id}/original`));
  assert.equal(verifyBlob(id, "original", exp, sig, 1_000_000), true);
  assert.equal(verifyBlob(id, "thumb", exp, sig, 1_000_000), false);
  assert.equal(verifyBlob(randomUUID(), "original", exp, sig, 1_000_000), false);
  assert.equal(verifyBlob(id, "original", exp, sig, 1_000_000 + 3_700_000), false);
  assert.equal(verifyBlob(id, "original", String(Number(exp) + 1), sig, 1_000_000), false);
  assert.equal(verifyBlob(id, "original", exp, "0".repeat(64), 1_000_000), false);
});

test("backfill transforms seal plaintext once and are idempotent", async () => {
  const c = await userCrypto(randomUUID());
  const conv = { title: "Visa plan", preview: "my visa", summary: "s", summaryHash: "a".repeat(40) };
  const p1 = conversationPatch(c, conv)!;
  assert.ok(isSealed(p1.title as string) && isSealed(p1.preview as string) && isSealed(p1.summary as string));
  assert.match(p1.summaryHash as string, /^h1:/);
  assert.equal(conversationPatch(c, p1 as typeof conv), null);

  const m = { content: "hello", citations: [{ id: "1", title: "t" }], images: [], evidence: [], meta: {}, table: null };
  const mp = messagePatch(c, m)!;
  assert.deepEqual(Object.keys(mp).sort(), ["citations", "content"]); // empty / null JSON is left alone
  assert.equal(messagePatch(c, { ...m, ...(mp as object) } as typeof m), null);

  const mem = memoryPatch(c, { text: "Uses Neovim.", slot: "tool:neovim", slotEnc: null })!;
  assert.ok(isSealed(mem.text as string) && isSealed(mem.slotEnc as string));
  assert.match(mem.slot as string, /^h1:/);
  assert.equal(c.open("memories", "slot_enc", mem.slotEnc as string), "tool:neovim");
  assert.equal(memoryPatch(c, mem as { text: string; slot: string; slotEnc: string }), null);

  assert.equal(keyHash(c, "chunks", "content_hash", "abc")?.startsWith("h1:"), true);
  assert.equal(keyHash(c, "chunks", "content_hash", keyHash(c, "chunks", "content_hash", "abc")), undefined);
  assert.equal(sealJsonValue(c, MSG, "meta", {}), undefined);

  const o = parseArgs(["--dry-run", "--only=messages,kb", "--batch=50", "--no-objects"]);
  assert.deepEqual([o.dryRun, o.batch, o.objects, [...o.only!]], [true, 50, false, ["messages", "kb"]]);
  assert.throws(() => parseArgs(["--only=nope"]));
});

test("telemetry and cache hold no user content", () => {
  // Cache rows are keyed by a hash of the (query / url) identity.
  const key = storedKey("brave|day|how to treat my rare disease");
  assert.match(key, /^h:[0-9a-f]{40}$/);
  assert.ok(!key.includes("disease"));
  // Upstream error text that quotes the request is cut down.
  const msg = scrub('Groq 400: invalid input "my diagnosis is a rare thing and here is my address" in field messages');
  assert.ok(!msg!.includes("diagnosis"));
  assert.ok(msg!.includes("400"));
});

test("CORS never trusts plain-HTTP origins in production", async () => {
  const ask = (o: ReturnType<typeof corsOptions>, origin?: string) =>
    new Promise<boolean>((resolve) => (o.origin as (o: string | undefined, cb: (e: Error | null, ok?: unknown) => void) => void)(origin, (_e, ok) => resolve(!!ok)));
  const prod = corsOptions({ production: true });
  assert.equal(await ask(prod, undefined), true); // the native app sends no Origin
  assert.equal(await ask(prod, "https://sparky.cloudnsofts.com"), true);
  assert.equal(await ask(prod, "http://evil.example"), false);
  assert.equal(await ask(prod, "http://localhost:3000"), false);
  const dev = corsOptions({ production: false });
  assert.equal(await ask(dev, "http://localhost:3000"), true);
  assert.equal(await ask(dev, "http://evil.example"), false);
});

test("production refuses to start without DATA_KEY; development derives a warning-only key", () => {
  config.dataKey = undefined;
  config.production = true;
  resetMasterKeysForTests();
  assert.throws(() => currentMasterKeyId(), /DATA_KEY is required/);
  config.production = false;
  resetMasterKeysForTests();
  assert.match(currentMasterKeyId(), /^[0-9a-f]{8}$/);
});

test("security headers: HSTS and strict defaults on JSON, HTML keeps its own policy, plain-HTTP requests are refused in production", async () => {
  const { default: express } = await import("express");
  const { httpsOnly, securityHeaders } = await import("../src/util/security.js");
  const app = express();
  app.use(securityHeaders({ production: true }));
  app.use(httpsOnly({ production: true }));
  app.get("/api", (_req, res) => void res.json({ ok: true }));
  app.get("/page", (_req, res) => void res.type("html").send("<p>hi</p>"));
  app.get("/health", (_req, res) => void res.json({ ok: true }));
  const server = await new Promise<import("node:http").Server>((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  const base = `http://127.0.0.1:${(server.address() as import("node:net").AddressInfo).port}`;
  try {
    const api = await fetch(`${base}/api`);
    assert.match(api.headers.get("strict-transport-security") ?? "", /max-age=31536000; includeSubDomains/);
    assert.equal(api.headers.get("x-content-type-options"), "nosniff");
    assert.equal(api.headers.get("x-frame-options"), "DENY");
    assert.equal(api.headers.get("referrer-policy"), "no-referrer");
    assert.equal(api.headers.get("cache-control"), "no-store");
    assert.match(api.headers.get("content-security-policy") ?? "", /default-src 'none'/);
    const page = await fetch(`${base}/page`);
    assert.equal(page.headers.get("content-security-policy"), null);
    // The proxy says the request came in over plain HTTP: GET is redirected to https, writes are refused, /health is exempt.
    const redirected = await fetch(`${base}/api?x=1`, { headers: { "x-forwarded-proto": "http" }, redirect: "manual" });
    assert.equal(redirected.status, 308);
    assert.match(redirected.headers.get("location") ?? "", /^https:\/\/127\.0\.0\.1:\d+\/api\?x=1$/);
    assert.equal((await fetch(`${base}/api`, { method: "POST", headers: { "x-forwarded-proto": "http" } })).status, 426);
    assert.equal((await fetch(`${base}/health`, { headers: { "x-forwarded-proto": "http" } })).status, 200);
    assert.equal((await fetch(`${base}/api`, { headers: { "x-forwarded-proto": "https" } })).status, 200);
  } finally {
    await new Promise((r) => server.close(r));
  }
});
