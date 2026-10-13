import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";

// Config reads the environment on import, so set it first and import the code afterwards.
process.env.CONNECTIONS_KEY = randomBytes(32).toString("base64");
process.env.GROQ_API_KEY = "gsk_SERVERKEYserverkey0000000000";

const GROQ_USER_KEY = "gsk_" + "u".repeat(24);
const GROQ_OTHER_KEY = "gsk_" + "o".repeat(24);

const { default: express } = await import("express");
const { runAs } = await import("../src/auth/context.js");
const { encryptSecret, decryptSecret } = await import("../src/connections/crypto.js");
const store = await import("../src/keys/store.js");
const { keysRouter, myUsageRouter, deps } = await import("../src/routes/keys.js");
const { checkKey, classifyCheck } = await import("../src/keys/check.js");
const usage = await import("../src/keys/usage.js");
const { streamModel, UpstreamError } = await import("../src/providers.js");
const { runChat } = await import("../src/llm/router.js");
const { errorMiddleware } = await import("../src/util/errors.js");
const { resetQuota } = await import("../src/llm/quota.js");
const { resetBudget } = await import("../src/llm/budget.js");
const { clearCooldown, cooldownUntil } = await import("../src/models.js");

type Row = import("../src/keys/store.js").KeyRow;

/** In-memory repo standing in for Postgres. */
function memRepo() {
  const rows = new Map<string, Row>();
  const k = (u: string, p: string) => `${u}|${p}`;
  const repo: import("../src/keys/store.js").KeyRepo = {
    async list(u) {
      return [...rows.values()].filter((r) => r.userId === u);
    },
    async get(u, p) {
      return rows.get(k(u, p)) ?? null;
    },
    async upsert(r) {
      const row: Row = { ...r, status: "untested", lastCheckedAt: null, createdAt: new Date() };
      rows.set(k(r.userId, r.provider), row);
      return row;
    },
    async setStatus(u, p, status, at) {
      const r = rows.get(k(u, p));
      if (r) Object.assign(r, { status, lastCheckedAt: at });
    },
    async remove(u, p) {
      return rows.delete(k(u, p));
    },
  };
  return { repo, rows };
}

let server: Server;
let base = "";
let mem = memRepo();
let currentUserId = "11111111-1111-1111-1111-111111111111";

before(async () => {
  mem = memRepo();
  store.setKeyRepo(mem.repo);
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    req.user = { id: currentUserId, role: "user", sid: null, bypass: false };
    runAs(req.user, next);
  });
  app.use("/me/keys", keysRouter);
  app.use("/me/usage", myUsageRouter);
  app.use(errorMiddleware);
  await new Promise<void>((r) => (server = app.listen(0, r)));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(() => {
  server.close();
  store.setKeyRepo(null);
});

const call = async (method: string, path: string, body?: unknown) => {
  const res = await fetch(base + path, { method, headers: { "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  return { status: res.status, text, json: text ? JSON.parse(text) : null };
};

test("encryptSecret/decryptSecret round-trips a provider key and hides it in the ciphertext", () => {
  const enc = encryptSecret(GROQ_USER_KEY);
  assert.ok(enc.startsWith("v1:"));
  assert.ok(!enc.includes(GROQ_USER_KEY));
  assert.equal(decryptSecret(enc), GROQ_USER_KEY);
});

test("key CRUD never returns the plaintext key; only the last 4 characters and a status", async () => {
  deps.check = async () => "valid";
  const put = await call("PUT", "/me/keys/groq", { key: ` ${GROQ_USER_KEY} ` });
  assert.equal(put.status, 200);
  assert.equal(put.json.result, "valid");
  assert.equal(put.json.key.hint, GROQ_USER_KEY.slice(-4));
  assert.equal(put.json.key.status, "valid");

  const list = await call("GET", "/me/keys");
  assert.equal(list.status, 200);
  assert.equal(list.json.hasValidKey, true);
  const groq = list.json.providers.find((p: { id: string }) => p.id === "groq");
  assert.equal(groq.key.hint, GROQ_USER_KEY.slice(-4));
  assert.ok(groq.keyUrl.startsWith("https://"));
  for (const r of [put, list]) {
    assert.ok(!r.text.includes(GROQ_USER_KEY), "plaintext key leaked");
    assert.ok(!/key_?enc|v1:/i.test(r.text), "ciphertext leaked");
  }
  // What sits in storage is encrypted.
  const stored = mem.rows.get(`${currentUserId}|groq`)!;
  assert.notEqual(stored.keyEnc, GROQ_USER_KEY);
  assert.equal(decryptSecret(stored.keyEnc), GROQ_USER_KEY);

  const del = await call("DELETE", "/me/keys/groq");
  assert.equal(del.status, 200);
  assert.equal(mem.rows.size, 0);
  assert.equal((await call("GET", "/me/keys")).json.hasValidKey, false);
});

test("PUT rejects a malformed key and an unknown provider; nothing is stored", async () => {
  deps.check = async () => assert.fail("must not call the provider");
  assert.equal((await call("PUT", "/me/keys/groq", { key: "not-a-key" })).status, 400);
  assert.equal((await call("PUT", "/me/keys/groq", { key: "sk-or-" + "a".repeat(30) })).status, 400);
  assert.equal((await call("PUT", "/me/keys/nope", { key: GROQ_USER_KEY })).status, 404);
  assert.equal(mem.rows.size, 0);
});

test("keys are per user: another user sees none and cannot test or delete mine", async () => {
  deps.check = async () => "valid";
  await call("PUT", "/me/keys/groq", { key: GROQ_USER_KEY });
  currentUserId = "22222222-2222-2222-2222-222222222222";
  try {
    const list = await call("GET", "/me/keys");
    assert.ok(list.json.providers.every((p: { key: unknown }) => p.key === null));
    assert.equal((await call("POST", "/me/keys/groq/test")).status, 404);
    await call("DELETE", "/me/keys/groq");
  } finally {
    currentUserId = "11111111-1111-1111-1111-111111111111";
  }
  assert.equal(mem.rows.size, 1);
  await call("DELETE", "/me/keys/groq");
});

test("test endpoint maps results to a status and friendly message; a network failure leaves the status alone", async () => {
  await call("PUT", "/me/keys/groq", { key: GROQ_USER_KEY });
  const expectations: Array<[import("../src/keys/check.js").CheckResult, string, string]> = [
    ["invalid", "invalid", "Key not accepted"],
    ["quota", "quota", "Out of credit"],
    ["valid", "valid", "Works"],
  ];
  for (const [result, status, message] of expectations) {
    deps.check = async () => result;
    const r = await call("POST", "/me/keys/groq/test");
    assert.equal(r.json.status, status);
    assert.equal(r.json.message, message);
  }
  deps.check = async () => "network";
  const net = await call("POST", "/me/keys/groq/test");
  assert.equal(net.json.result, "network");
  assert.equal(net.json.message, "Couldn't reach provider");
  assert.equal(mem.rows.get(`${currentUserId}|groq`)!.status, "valid", "unchanged by a network failure");
  await call("DELETE", "/me/keys/groq");
});

test("checkKey maps provider responses (mock fetch) and never throws", async () => {
  const reply = (status: number, body = "") => (async () => new Response(body, { status })) as unknown as typeof fetch;
  assert.equal(await checkKey("groq", GROQ_USER_KEY, reply(200, "{}")), "valid");
  assert.equal(await checkKey("groq", GROQ_USER_KEY, reply(401, "bad key")), "invalid");
  assert.equal(await checkKey("openrouter", "sk-or-x", reply(402, "")), "quota");
  assert.equal(await checkKey("nvidia", "nvapi-x", reply(429, "You exceeded your current quota")), "quota");
  assert.equal(await checkKey("ollama", "x", reply(429, "slow down")), "valid");
  assert.equal(await checkKey("groq", GROQ_USER_KEY, reply(503)), "network");
  assert.equal(await checkKey("groq", GROQ_USER_KEY, (async () => { throw new Error("ENOTFOUND"); }) as unknown as typeof fetch), "network");
  const seen: string[] = [];
  await checkKey("groq", GROQ_USER_KEY, (async (url: string, init: RequestInit) => { seen.push(String(url), String((init.headers as Record<string, string>).Authorization)); return new Response("{}"); }) as unknown as typeof fetch);
  assert.deepEqual(seen, ["https://api.groq.com/openai/v1/models", `Bearer ${GROQ_USER_KEY}`]);
  assert.equal(classifyCheck(404, ""), "valid");
});

// ---- routing -------------------------------------------------------------------

const sse = (text: string) => new Response(`data: ${JSON.stringify({ choices: [{ delta: { content: text } }] })}\n\ndata: ${JSON.stringify({ choices: [{ finish_reason: "stop", delta: {} }], usage: { prompt_tokens: 3, completion_tokens: 2 } })}\n\ndata: [DONE]\n\n`, { status: 200 });

async function withFetch<T>(impl: (auth: string) => Response, fn: (auths: string[]) => Promise<T>): Promise<T> {
  const real = globalThis.fetch;
  const auths: string[] = [];
  globalThis.fetch = (async (_url: unknown, init?: RequestInit) => {
    const auth = String((init?.headers as Record<string, string>)?.Authorization ?? "");
    auths.push(auth);
    return impl(auth);
  }) as typeof fetch;
  try {
    return await fn(auths);
  } finally {
    globalThis.fetch = real;
  }
}

const asUser = <T>(id: string, fn: () => Promise<T>): Promise<T> => new Promise((resolve, reject) => runAs({ id, role: "user", sid: null, bypass: false }, () => fn().then(resolve, reject)));
const drain = async (h: { tokens: AsyncGenerator<string> }) => {
  let s = "";
  for await (const t of h.tokens) s += t;
  return s;
};

async function giveKey(userId: string, key: string, status: "valid" | "invalid" = "valid") {
  await mem.repo.upsert({ userId, provider: "groq", label: "", keyEnc: encryptSecret(key), keyHint: key.slice(-4) });
  await mem.repo.setStatus(userId, "groq", status, new Date());
  store.dropCached(userId);
}

test("routing: a user with a valid key calls the provider with THEIR key; others keep the server key", async () => {
  resetQuota();
  resetBudget();
  mem = memRepo();
  store.setKeyRepo(mem.repo);
  await giveKey("u-a", GROQ_USER_KEY);
  await giveKey("u-b", GROQ_OTHER_KEY);
  const model = "groq:openai/gpt-oss-20b";
  await withFetch(() => sse("hi"), async (auths) => {
    const ha = await asUser("u-a", async () => { const h = await streamModel(model, [{ role: "user", content: "x" }], { signal: new AbortController().signal, firstByteMs: 1000, idleMs: 1000 }); await drain(h); return h; });
    assert.equal(ha.keySource, "user");
    const hb = await asUser("u-b", async () => { const h = await streamModel(model, [{ role: "user", content: "x" }], { signal: new AbortController().signal, firstByteMs: 1000, idleMs: 1000 }); await drain(h); return h; });
    assert.equal(hb.keySource, "user");
    const hc = await asUser("u-nokey", async () => { const h = await streamModel(model, [{ role: "user", content: "x" }], { signal: new AbortController().signal, firstByteMs: 1000, idleMs: 1000 }); await drain(h); return h; });
    assert.equal(hc.keySource, "server");
    assert.deepEqual(auths, [`Bearer ${GROQ_USER_KEY}`, `Bearer ${GROQ_OTHER_KEY}`, `Bearer ${process.env.GROQ_API_KEY}`]);
  });
});

test("routing: a user key that is not valid is never used", async () => {
  mem = memRepo();
  store.setKeyRepo(mem.repo);
  await giveKey("u-bad", GROQ_USER_KEY, "invalid");
  await withFetch(() => sse("hi"), async (auths) => {
    await asUser("u-bad", async () => drain(await streamModel("groq:openai/gpt-oss-20b", [{ role: "user", content: "x" }], { signal: new AbortController().signal, firstByteMs: 1000, idleMs: 1000 })));
    assert.deepEqual(auths, [`Bearer ${process.env.GROQ_API_KEY}`]);
  });
});

test("runChat: a rejected user key is marked invalid, falls back to the server key once, and leaves server cooldowns untouched", async () => {
  resetQuota();
  resetBudget();
  mem = memRepo();
  store.setKeyRepo(mem.repo);
  await giveKey("u-fb", GROQ_USER_KEY);
  const model = "groq:openai/gpt-oss-20b";
  clearCooldown(model);
  const hooks = { onQueued() {}, onModel() {}, onDelta() {}, onReset() {}, onFallback() {} };
  await withFetch((auth) => (auth.includes(GROQ_USER_KEY) ? new Response(JSON.stringify({ error: { message: "Invalid API Key" } }), { status: 401 }) : sse("ok")), async (auths) => {
    const r = await asUser("u-fb", () => runChat([model], [{ role: "user", content: "x" }], new AbortController().signal, hooks, false));
    assert.equal(r.model, model);
    assert.deepEqual(auths, [`Bearer ${GROQ_USER_KEY}`, `Bearer ${process.env.GROQ_API_KEY}`]);
  });
  assert.equal(cooldownUntil(model), null, "the user's bad key must not cool the shared model down");
  assert.equal((await mem.repo.get("u-fb", "groq"))!.status, "invalid");
});

test("runChat: a user's rate limit on their own key does not cool the shared model for others", async () => {
  resetQuota();
  resetBudget();
  mem = memRepo();
  store.setKeyRepo(mem.repo);
  await giveKey("u-rl", GROQ_USER_KEY);
  const model = "groq:openai/gpt-oss-20b";
  clearCooldown(model);
  const hooks = { onQueued() {}, onModel() {}, onDelta() {}, onReset() {}, onFallback() {} };
  await withFetch(() => new Response(JSON.stringify({ error: { message: "Rate limit reached, try again in 20s" } }), { status: 429 }), async () => {
    await assert.rejects(asUser("u-rl", () => runChat([model], [{ role: "user", content: "x" }], new AbortController().signal, hooks, false)));
  });
  assert.equal(cooldownUntil(model), null);
  assert.ok(store.userCooldownUntil("u-rl", model) !== null, "cooldown is the user's own");
  assert.equal((await mem.repo.get("u-rl", "groq"))!.status, "valid", "a rate limit does not invalidate the key");
});

test("each user key gets its own concurrency pool, separate from the shared one", () => {
  const a = store.slotsForUserKey("u-1", "groq");
  assert.equal(a, store.slotsForUserKey("u-1", "groq"));
  assert.notEqual(a, store.slotsForUserKey("u-2", "groq"));
});

// ---- usage filtering -----------------------------------------------------------

const ev = (o: Partial<import("../src/db/usage.js").TelemetryEvent>): import("../src/db/usage.js").TelemetryEvent => ({
  id: "1", ts: "2026-10-13T10:00:00.000Z", provider: "groq", model: "openai/gpt-oss-20b", kind: "chat", purpose: "chat", ok: true, status: 200, errorCode: null, errorMessage: null,
  latencyMs: 100, ttftMs: 10, count: 1, promptTokens: 10, completionTokens: 5, attempt: 1, userId: "u1", requestId: null, conversationId: null, keySource: "user", ...o,
});

test("usage is filtered to the caller's own chat calls on their own keys", () => {
  const events = [
    ev({}),
    ev({ id: "2", ok: false, promptTokens: null, completionTokens: null, latencyMs: 300 }),
    ev({ id: "3", keySource: "server" }), // the caller's call on the server key
    ev({ id: "4", userId: "u2" }), // another user's key usage
    ev({ id: "5", userId: null, keySource: "server" }),
    ev({ id: "6", kind: "embed" }),
    ev({ id: "7", ts: "2026-09-01T10:00:00.000Z" }), // outside the window
  ];
  const rows = usage.bucketEvents(events, "u1", new Date("2026-10-07T00:00:00Z"));
  const out = usage.aggregateKeyUsage(rows, 7, new Date("2026-10-13T12:00:00Z"));
  assert.equal(out.totals.requests, 2);
  assert.equal(out.totals.errors, 1);
  assert.equal(out.totals.tokens, 15);
  assert.equal(out.totals.avgLatencyMs, 200);
  assert.equal(out.byDay.length, 7);
  assert.equal(out.byDay.at(-1)!.day, "2026-10-13");
  assert.equal(out.byDay.at(-1)!.requests, 2);
  assert.deepEqual(out.byModel.map((m) => [m.provider, m.model, m.requests]), [["groq", "openai/gpt-oss-20b", 2]]);
  assert.deepEqual(usage.aggregateKeyUsage(usage.bucketEvents(events, "nobody", new Date(0)), 7).totals.requests, 0);
});

test("GET /me/usage/keys is only enabled with a valid key and rejects odd windows", async () => {
  mem = memRepo();
  store.setKeyRepo(mem.repo);
  assert.equal((await call("GET", "/me/usage/keys?days=9")).status, 400);
  const none = await call("GET", "/me/usage/keys?days=7");
  assert.equal(none.json.enabled, false);
  assert.equal(none.json.totals.requests, 0);
  await giveKey(currentUserId, GROQ_USER_KEY);
  assert.equal((await call("GET", "/me/usage/keys?days=30")).json.enabled, true);
});

test("UpstreamError carries the userKey flag only when set", () => {
  assert.equal(new UpstreamError(401, "x").userKey, undefined);
});
