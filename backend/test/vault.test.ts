import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import express from "express";
import { hashPassword } from "../src/auth/service.js";
import { runAs, type AuthUser } from "../src/auth/context.js";
import { errorMiddleware } from "../src/util/errors.js";
import { AttemptLimiter, openVault, sealVault } from "../src/vault/crypto.js";
import { VAULT_KIND, rewrapVault, vaultRouter, type VaultRow, type VaultStore } from "../src/vault/service.js";

const OWNER = "11111111-1111-1111-1111-111111111111";
const OTHER = "22222222-2222-2222-2222-222222222222";
const KEY = "dGhpcy1pcy1hLXRlc3QtZGF0YS1rZXktMzItYnl0ZXM=";
const PW = "correct horse battery";

function memStore(): VaultStore & { rows: Map<string, VaultRow> } {
  const rows = new Map<string, VaultRow>();
  return {
    rows,
    async get(u, k) {
      return rows.get(`${u}:${k}`) ?? null;
    },
    async put(u, k, v) {
      const now = new Date();
      rows.set(`${u}:${k}`, { userId: u, kind: k, ...v, createdAt: rows.get(`${u}:${k}`)?.createdAt ?? now, updatedAt: now });
    },
    async markReseal(u, k) {
      const r = rows.get(`${u}:${k}`);
      if (r) rows.set(`${u}:${k}`, { ...r, params: { ...r.params, needsReseal: true } });
    },
  };
}

let server: Server;
let base: string;
let store: ReturnType<typeof memStore>;
let limiter: AttemptLimiter;
let hash: string;
let noPassword = false;

before(async () => {
  hash = await hashPassword(PW);
  store = memStore();
  limiter = new AttemptLimiter();
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    const who = String(req.headers["x-test-user"] ?? "owner");
    const user: AuthUser = who === "user" ? { id: OTHER, role: "user", sid: "s", bypass: false } : { id: OWNER, role: "owner", sid: "s", bypass: false };
    req.user = user;
    runAs(user, next);
  });
  app.use(
    "/admin/vault",
    vaultRouter({ store, limiter, dataKey: () => KEY, passwordHashOf: async (id) => (id === OWNER ? (noPassword ? null : hash) : undefined) }),
  );
  app.use(errorMiddleware);
  server = app.listen(0);
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}/admin/vault`;
});
after(() => server.close());

const call = (path: string, init: { method?: string; body?: unknown; user?: string } = {}) =>
  fetch(base + path, {
    method: init.method ?? "GET",
    headers: { "content-type": "application/json", "x-test-user": init.user ?? "owner" },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });

test("non-owner gets 403 on every vault route", async () => {
  for (const [p, m] of [["", "GET"], ["/seed", "POST"], ["/reveal", "POST"]] as const) {
    const r = await call(p, { method: m, body: m === "POST" ? { password: PW } : undefined, user: "user" });
    assert.equal(r.status, 403, p);
  }
});

test("status before seeding, then seed, status, reveal round-trip", async () => {
  store.rows.clear();
  let s = await (await call("")).json();
  assert.deepEqual({ exists: s.exists, needsReseal: s.needsReseal }, { exists: false, needsReseal: false });
  const seed = await call("/seed", { method: "POST", body: { password: PW } });
  assert.equal(seed.status, 200);
  assert.equal(seed.headers.get("cache-control"), "no-store");
  s = await (await call("")).json();
  assert.equal(s.exists, true);
  assert.equal(s.kind, VAULT_KIND);
  assert.ok(!JSON.stringify(s).includes(KEY));
  const rev = await call("/reveal", { method: "POST", body: { password: PW } });
  assert.equal(rev.status, 200);
  assert.equal(rev.headers.get("cache-control"), "no-store");
  assert.equal((await rev.json()).secret, KEY);
});

test("stored row has no plaintext and no derived key; params are scrypt", async () => {
  const row = store.rows.get(`${OWNER}:${VAULT_KIND}`)!;
  const dump = JSON.stringify(row);
  assert.ok(!dump.includes(KEY));
  assert.ok(!Buffer.from(row.ciphertext, "base64").includes(Buffer.from(KEY)));
  assert.equal(row.params.kdf, "scrypt");
  assert.equal(row.params.N, 2 ** 17);
});

test("wrong password is rejected on seed and reveal; GET is not a password route", async () => {
  limiter.success(OWNER);
  assert.equal((await call("/reveal", { method: "POST", body: { password: "nope" } })).status, 403);
  assert.equal((await call("/seed", { method: "POST", body: { password: "nope" } })).status, 403);
  assert.equal((await call("/reveal", { method: "POST", body: {} })).status, 400);
  assert.equal((await call("/reveal?password=" + PW)).status, 404);
  limiter.success(OWNER);
});

test("lockout after 5 wrong passwords, even for the right one", async () => {
  limiter.success(OWNER);
  for (let i = 0; i < 5; i++) assert.equal((await call("/reveal", { method: "POST", body: { password: "bad" + i } })).status, 403);
  const locked = await call("/reveal", { method: "POST", body: { password: PW } });
  assert.equal(locked.status, 429);
  assert.equal((await locked.json()).error.code, "vault_locked");
  limiter.success(OWNER);
});

test("limiter: window, lock expiry", () => {
  let t = 0;
  const l = new AttemptLimiter(5, 15 * 60_000, 15 * 60_000, () => t);
  for (let i = 0; i < 4; i++) l.fail("a");
  assert.equal(l.lockedFor("a"), 0);
  t = 16 * 60_000; // old failures fall out of the window
  l.fail("a");
  assert.equal(l.lockedFor("a"), 0);
  for (let i = 0; i < 4; i++) l.fail("a");
  assert.ok(l.lockedFor("a") > 0);
  t += 15 * 60_000 + 1;
  assert.equal(l.lockedFor("a"), 0);
});

test("SSO-only owner (no password) is told to set one", async () => {
  noPassword = true;
  const r = await call("/seed", { method: "POST", body: { password: "whatever" } });
  noPassword = false;
  assert.equal(r.status, 409);
  assert.equal((await r.json()).error.code, "password_not_set");
});

test("AAD binds the ciphertext to user and kind", async () => {
  const sealed = await sealVault(PW, KEY, OWNER, VAULT_KIND);
  assert.equal(await openVault(PW, sealed, OWNER, VAULT_KIND), KEY);
  await assert.rejects(openVault(PW, sealed, OTHER, VAULT_KIND));
  await assert.rejects(openVault(PW, sealed, OWNER, "other_kind"));
  await assert.rejects(openVault("wrong", sealed, OWNER, VAULT_KIND));
});

test("password change re-wraps the vault (new opens, old no longer does)", async () => {
  const s = memStore();
  await s.put(OWNER, VAULT_KIND, await sealVault(PW, KEY, OWNER, VAULT_KIND));
  assert.equal(await rewrapVault(OWNER, PW, "brand new pass", s), "rewrapped");
  const row = s.rows.get(`${OWNER}:${VAULT_KIND}`)!;
  assert.equal(await openVault("brand new pass", row, OWNER, VAULT_KIND), KEY);
  await assert.rejects(openVault(PW, row, OWNER, VAULT_KIND));
});

test("password change without the old password or with a wrong one marks needs re-seal", async () => {
  const s = memStore();
  assert.equal(await rewrapVault(OWNER, PW, "x", s), "none");
  await s.put(OWNER, VAULT_KIND, await sealVault(PW, KEY, OWNER, VAULT_KIND));
  assert.equal(await rewrapVault(OWNER, undefined, "new pass 123", s), "needs_reseal");
  assert.equal(s.rows.get(`${OWNER}:${VAULT_KIND}`)!.params.needsReseal, true);
  const s2 = memStore();
  await s2.put(OWNER, VAULT_KIND, await sealVault(PW, KEY, OWNER, VAULT_KIND));
  assert.equal(await rewrapVault(OWNER, "wrong", "new pass 123", s2), "needs_reseal");
});

test("needs-reseal vault reports it and refuses to reveal; re-seeding clears it", async () => {
  store.rows.clear();
  limiter.success(OWNER);
  await call("/seed", { method: "POST", body: { password: PW } });
  await store.markReseal(OWNER, VAULT_KIND);
  assert.equal((await (await call("")).json()).needsReseal, true);
  const rev = await call("/reveal", { method: "POST", body: { password: PW } });
  assert.equal(rev.status, 409);
  await call("/seed", { method: "POST", body: { password: PW } });
  assert.equal((await (await call("")).json()).needsReseal, false);
});

test("no password, key or derived material in logs", async () => {
  const lines: string[] = [];
  const orig = { log: console.log, warn: console.warn, error: console.error };
  console.log = console.warn = console.error = (...a: unknown[]) => void lines.push(a.join(" "));
  try {
    limiter.success(OWNER);
    await call("/seed", { method: "POST", body: { password: PW } });
    await call("/reveal", { method: "POST", body: { password: PW } });
    await call("/reveal", { method: "POST", body: { password: "SECRETWRONGPW" } });
    limiter.success(OWNER);
  } finally {
    Object.assign(console, orig);
  }
  const all = lines.join("\n");
  assert.ok(lines.length > 0);
  for (const bad of [PW, "SECRETWRONGPW", KEY]) assert.ok(!all.includes(bad), bad);
});
