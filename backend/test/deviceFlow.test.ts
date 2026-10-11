import { test } from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { ACCESS_TOKEN_URL, DEVICE_CODE_URL, DeviceFlows, GITHUB_USER_URL, type ConnectionRow } from "../src/connections/deviceFlow.js";
import { decryptSecret, encryptSecret } from "../src/connections/crypto.js";
import { AppError } from "../src/util/errors.js";

/** A scripted GitHub: device code, a queue of token-endpoint answers, /user. No network. */
function harness(tokenAnswers: object[], opts: { clientId?: string; deviceCode?: object } = {}) {
  let now = 1_000_000;
  const key = randomBytes(32);
  const saved: ConnectionRow[] = [];
  const calls: { url: string; at: number; body?: string }[] = [];
  const json = (body: object, status = 200, headers: Record<string, string> = {}) =>
    new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...headers } });
  const fakeFetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, at: now, body: typeof init?.body === "string" ? init.body : undefined });
    if (url === DEVICE_CODE_URL) {
      return json(
        opts.deviceCode ?? {
          device_code: "dev-123",
          user_code: "ABCD-1234",
          verification_uri: "https://github.com/login/device",
          expires_in: 900,
          interval: 5,
        },
      );
    }
    if (url === ACCESS_TOKEN_URL) return json(tokenAnswers.shift() ?? { error: "authorization_pending" });
    if (url === GITHUB_USER_URL) {
      assert.equal((init?.headers as Record<string, string>).Authorization, "Bearer gho_secret_token");
      return json({ login: "octocat", id: 583231, avatar_url: "https://avatars.example/octocat" }, 200, { "x-oauth-scopes": "repo, read:org" });
    }
    throw new Error(`unexpected fetch ${url}`);
  }) as typeof fetch;
  const flows = new DeviceFlows({
    clientId: () => ("clientId" in opts ? opts.clientId : "Iv1.test"),
    fetch: fakeFetch,
    now: () => now,
    encrypt: (plain) => encryptSecret(plain, key),
    save: async (row) => {
      saved.push(row);
    },
  });
  return {
    flows,
    saved,
    calls,
    key,
    tick: (s: number) => {
      now += s * 1000;
    },
    tokenCalls: () => calls.filter((c) => c.url === ACCESS_TOKEN_URL),
  };
}

test("not configured: start throws 503 github_oauth_not_configured", async () => {
  const h = harness([], { clientId: undefined });
  await assert.rejects(h.flows.start("u1"), (e: unknown) => e instanceof AppError && e.status === 503 && e.code === "github_oauth_not_configured");
  assert.equal(h.calls.length, 0);
});

test("start requests the right scopes and returns the user code", async () => {
  const h = harness([]);
  const s = await h.flows.start("u1");
  assert.equal(s.userCode, "ABCD-1234");
  assert.equal(s.interval, 5);
  assert.equal(s.expiresIn, 900);
  const body = new URLSearchParams(h.calls[0].body);
  assert.equal(body.get("client_id"), "Iv1.test");
  assert.equal(body.get("scope"), "repo read:user read:org");
});

test("polls GitHub at most once per interval, however often the client asks", async () => {
  const h = harness([{ error: "authorization_pending" }, { error: "authorization_pending" }]);
  const { flowId } = await h.flows.start("u1");
  // Before the first interval: no GitHub call.
  assert.equal((await h.flows.poll("u1", flowId)).status, "pending");
  h.tick(2);
  await h.flows.poll("u1", flowId);
  assert.equal(h.tokenCalls().length, 0);
  h.tick(3);
  assert.equal((await h.flows.poll("u1", flowId)).status, "pending");
  assert.equal(h.tokenCalls().length, 1);
  h.tick(1);
  await h.flows.poll("u1", flowId);
  await h.flows.poll("u1", flowId);
  assert.equal(h.tokenCalls().length, 1);
  h.tick(4);
  await h.flows.poll("u1", flowId);
  assert.equal(h.tokenCalls().length, 2);
  // The grant type and device code go along.
  const body = new URLSearchParams(h.tokenCalls()[0].body);
  assert.equal(body.get("grant_type"), "urn:ietf:params:oauth:grant-type:device_code");
  assert.equal(body.get("device_code"), "dev-123");
});

test("concurrent client polls share one GitHub request", async () => {
  const h = harness([{ error: "authorization_pending" }]);
  const { flowId } = await h.flows.start("u1");
  h.tick(5);
  await Promise.all([h.flows.poll("u1", flowId), h.flows.poll("u1", flowId), h.flows.poll("u1", flowId)]);
  assert.equal(h.tokenCalls().length, 1);
});

test("slow_down raises the interval (GitHub's value, or +5s)", async () => {
  const h = harness([{ error: "slow_down", interval: 10 }, { error: "slow_down" }, { error: "authorization_pending" }]);
  const { flowId } = await h.flows.start("u1");
  h.tick(5);
  const r1 = await h.flows.poll("u1", flowId);
  assert.equal(r1.status, "pending");
  assert.equal(r1.interval, 10);
  // The old 5 s interval is no longer enough.
  h.tick(5);
  await h.flows.poll("u1", flowId);
  assert.equal(h.tokenCalls().length, 1);
  h.tick(5);
  const r2 = await h.flows.poll("u1", flowId);
  assert.equal(h.tokenCalls().length, 2);
  assert.equal(r2.interval, 15);
  h.tick(14);
  await h.flows.poll("u1", flowId);
  assert.equal(h.tokenCalls().length, 2);
  h.tick(1);
  await h.flows.poll("u1", flowId);
  assert.equal(h.tokenCalls().length, 3);
});

test("expiry: local deadline and GitHub's expired_token both end the flow", async () => {
  const local = harness([]);
  const a = await local.flows.start("u1");
  local.tick(901);
  const r = await local.flows.poll("u1", a.flowId);
  assert.equal(r.status, "expired");
  assert.equal(local.tokenCalls().length, 0);
  // Terminal: no further GitHub calls.
  local.tick(10);
  assert.equal((await local.flows.poll("u1", a.flowId)).status, "expired");
  assert.equal(local.tokenCalls().length, 0);

  const remote = harness([{ error: "expired_token" }]);
  const b = await remote.flows.start("u1");
  remote.tick(5);
  assert.equal((await remote.flows.poll("u1", b.flowId)).status, "expired");
});

test("access_denied ends as denied", async () => {
  const h = harness([{ error: "access_denied" }]);
  const { flowId } = await h.flows.start("u1");
  h.tick(5);
  assert.equal((await h.flows.poll("u1", flowId)).status, "denied");
  assert.equal(h.saved.length, 0);
});

test("success stores an encrypted token and the account; poll never returns the token", async () => {
  const h = harness([{ error: "authorization_pending" }, { access_token: "gho_secret_token", token_type: "bearer", scope: "repo,read:org,read:user" }]);
  const { flowId } = await h.flows.start("u1");
  h.tick(5);
  await h.flows.poll("u1", flowId);
  h.tick(5);
  const r = await h.flows.poll("u1", flowId);
  assert.equal(r.status, "connected");
  assert.deepEqual(r.account, { login: "octocat", id: "583231", avatarUrl: "https://avatars.example/octocat", scopes: ["repo", "read:org", "read:user"] });
  assert.ok(!JSON.stringify(r).includes("gho_secret_token"));

  assert.equal(h.saved.length, 1);
  const row = h.saved[0];
  assert.equal(row.userId, "u1");
  assert.equal(row.login, "octocat");
  assert.ok(row.accessTokenEnc.startsWith("v1:"));
  assert.ok(!row.accessTokenEnc.includes("gho_secret_token"));
  assert.equal(decryptSecret(row.accessTokenEnc, h.key), "gho_secret_token");
  assert.equal(row.refreshTokenEnc, null);
  assert.equal(row.expiresAt, null);
  // A wrong key cannot read it (GCM authentication).
  assert.throws(() => decryptSecret(row.accessTokenEnc, randomBytes(32)));
});

test("flows are private to the user who started them", async () => {
  const h = harness([]);
  const { flowId } = await h.flows.start("u1");
  await assert.rejects(h.flows.poll("u2", flowId), (e: unknown) => e instanceof AppError && e.status === 404);
});

test("a new start replaces the user's pending flow", async () => {
  const h = harness([]);
  const a = await h.flows.start("u1");
  await h.flows.start("u1");
  await assert.rejects(h.flows.poll("u1", a.flowId), (e: unknown) => e instanceof AppError && e.status === 404);
});

test("device flow disabled on the app maps to not configured", async () => {
  const h = harness([], { deviceCode: { error: "device_flow_disabled" } });
  await assert.rejects(h.flows.start("u1"), (e: unknown) => e instanceof AppError && e.code === "github_oauth_not_configured");
});
