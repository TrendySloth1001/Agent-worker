import { after, test } from "node:test";
import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { ACCESS_TOKEN_URL, GITHUB_EMAILS_URL, GITHUB_USER_URL, type ConnectionRow } from "../src/connections/deviceFlow.js";
import { decryptSecret, encryptSecret } from "../src/connections/crypto.js";
import { GITHUB_SSO_SCOPES } from "../src/auth/githubSso.js";
import { GITHUB_SCOPES } from "../src/connections/deviceFlow.js";
import {
  AUTHORIZE_URL,
  createGithubWeb,
  DEEP_LINK,
  pkceChallenge,
  sha256,
  TICKET_TTL_MS,
  FLOW_TTL_MS,
  prismaWebStore,
  type WebFlowRow,
  type WebFlowStore,
} from "../src/auth/githubWeb.js";
import { callbackPage } from "../src/auth/githubWebPage.js";
import type { SsoProfile } from "../src/auth/sso.js";
import { AppError } from "../src/util/errors.js";
import { config } from "../src/config.js";
import { closeDb, db, initDb, onDbUp } from "../src/db/prisma.js";

const isApp = (status: number, code: string) => (e: unknown) => e instanceof AppError && e.status === status && e.code === code;
const REDIRECT = "https://sparky.example/auth/github/callback";

/** The same conditional writes as the Prisma store, in memory. */
function memoryStore(): WebFlowStore & { rows: WebFlowRow[] } {
  const rows: WebFlowRow[] = [];
  return {
    rows,
    async create(r) {
      rows.push({ ...r, id: randomUUID(), status: "pending", ticketHash: null, ticketExpiresAt: null, result: null });
    },
    async claim(stateHash, now) {
      const r = rows.find((x) => x.stateHash === stateHash && x.status === "pending" && x.expiresAt > now);
      if (!r) return null;
      r.status = "exchanging";
      return { ...r };
    },
    async ready(id, ticketHash, ticketExpiresAt, result) {
      Object.assign(rows.find((x) => x.id === id)!, { status: "ready", ticketHash, ticketExpiresAt, result, codeVerifier: "" });
    },
    async fail(id) {
      Object.assign(rows.find((x) => x.id === id)!, { status: "failed", codeVerifier: "" });
    },
    async byTicket(h) {
      const r = rows.find((x) => x.ticketHash === h);
      return r ? { ...r } : null;
    },
    async consume(h, now, userId) {
      const r = rows.find(
        (x) => x.ticketHash === h && x.status === "ready" && x.ticketExpiresAt! > now && (userId ? x.userId === userId : x.mode === "signin"),
      );
      if (!r) return false;
      r.status = "redeemed";
      return true;
    },
    async purge() {},
  };
}

function harness(opts: { tokenAnswer?: object; secret?: string | undefined; resolve?: (p: SsoProfile) => Promise<never> } = {}) {
  let now = 5_000_000;
  const key = randomBytes(32);
  const store = memoryStore();
  const tokenCalls: URLSearchParams[] = [];
  const saved: ConnectionRow[] = [];
  const resolved: SsoProfile[] = [];
  const linked: { userId: string; profile: SsoProfile }[] = [];
  const sessions: { userId: string; device: string | null }[] = [];
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
  const fakeFetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    if (url === ACCESS_TOKEN_URL) {
      tokenCalls.push(new URLSearchParams(String(init?.body)));
      return json(opts.tokenAnswer ?? { access_token: "gho_web_token", scope: "repo,read:org,read:user,user:email", token_type: "bearer" });
    }
    if (url === GITHUB_USER_URL) {
      assert.equal((init?.headers as Record<string, string>).Authorization, "Bearer gho_web_token");
      return json({ login: "octocat", id: 583231, name: "The Octocat", email: null, avatar_url: "https://avatars.example/octocat" });
    }
    if (url === GITHUB_EMAILS_URL) return json([{ email: "octo@example.com", primary: true, verified: true }]);
    throw new Error(`unexpected fetch ${url}`);
  }) as typeof fetch;
  const web = createGithubWeb({
    clientId: () => "Iv1.test",
    clientSecret: () => ("secret" in opts ? opts.secret : "shh-secret"),
    redirectUri: () => REDIRECT,
    fetch: fakeFetch,
    now: () => now,
    store,
    resolve:
      opts.resolve ??
      (async (p) => {
        resolved.push(p);
        return { user: { id: "user-new" }, outcome: "created" };
      }),
    link: async (userId, profile) => {
      linked.push({ userId, profile });
      return { id: "ident-1", provider: "github", email: profile.email, login: profile.login, createdAt: "" };
    },
    encrypt: (plain) => encryptSecret(plain, key),
    saveConnection: async (row) => {
      saved.push(row);
    },
    session: async (userId, device) => {
      sessions.push({ userId, device });
      return {
        user: { id: userId, role: "user" } as never,
        tokens: { accessToken: "a", accessExpiresAt: "", refreshToken: "r", refreshExpiresAt: "", sessionId: "s" },
      };
    },
    connection: async (userId) => ({
      provider: "github",
      accountLogin: "octocat",
      accountId: "583231",
      avatarUrl: null,
      scopes: ["repo"],
      expiresAt: null,
      createdAt: userId,
      updatedAt: "",
      lastUsedAt: null,
    }),
  });
  return { web, store, key, tokenCalls, saved, resolved, linked, sessions, tick: (ms: number) => void (now += ms) };
}

const linkParams = (link: string) => {
  assert.ok(link.startsWith(`${DEEP_LINK}?`), link);
  return new URLSearchParams(link.slice(DEEP_LINK.length + 1));
};

test("web start: authorize URL with callback, scopes, state and an S256 challenge; only hashes stored", async () => {
  const h = harness();
  const s = await h.web.start({ mode: "signin", userId: null, device: "Pixel" });
  const url = new URL(s.authorizeUrl);
  assert.equal(`${url.origin}${url.pathname}`, AUTHORIZE_URL);
  const q = url.searchParams;
  assert.equal(q.get("client_id"), "Iv1.test");
  assert.equal(q.get("redirect_uri"), REDIRECT);
  assert.equal(q.get("scope"), GITHUB_SSO_SCOPES);
  assert.equal(q.get("state"), s.state);
  assert.equal(q.get("code_challenge_method"), "S256");
  assert.equal(q.get("allow_signup"), "true");
  assert.equal(s.expiresIn, FLOW_TTL_MS / 1000);
  const row = h.store.rows[0];
  assert.equal(row.stateHash, sha256(s.state));
  assert.ok(!JSON.stringify(row).includes(s.state));
  assert.equal(q.get("code_challenge"), pkceChallenge(row.codeVerifier));
  assert.ok(row.codeVerifier.length >= 43);
  assert.equal(row.device, "Pixel");
  assert.equal(row.userId, null);
});

test("web start: needs the client secret; connect/link need a user, sign-in must not have one", async () => {
  await assert.rejects(harness({ secret: undefined }).web.start({ mode: "signin", userId: null, device: null }), isApp(503, "github_oauth_not_configured"));
  const h = harness();
  await assert.rejects(h.web.start({ mode: "connect", userId: null, device: null }), isApp(403, "forbidden"));
  await assert.rejects(h.web.start({ mode: "link", userId: null, device: null }), isApp(403, "forbidden"));
  await assert.rejects(h.web.start({ mode: "signin", userId: "u1", device: null }), isApp(403, "forbidden"));
  assert.equal(h.web.configured(), true);
});

test("web callback: a state that matches no flow is rejected without asking GitHub", async () => {
  const h = harness();
  const s = await h.web.start({ mode: "signin", userId: null, device: null });
  const cb = await h.web.callback({ code: "c0de", state: `${s.state}x` });
  assert.equal(cb.ok, false);
  const p = linkParams(cb.link);
  assert.equal(p.get("error"), "expired");
  assert.equal(p.get("ticket"), null);
  assert.equal(h.tokenCalls.length, 0);
  // Missing state as well.
  assert.equal(linkParams((await h.web.callback({ code: "c0de" })).link).get("error"), "bad_request");
  assert.equal(h.tokenCalls.length, 0);
  // The real flow is still usable.
  assert.equal((await h.web.callback({ code: "c0de", state: s.state })).ok, true);
});

test("web callback: exchanges the code with the secret, redirect_uri and PKCE verifier; state works once", async () => {
  const h = harness();
  const s = await h.web.start({ mode: "signin", userId: null, device: null });
  const verifier = h.store.rows[0].codeVerifier;
  const cb = await h.web.callback({ code: "c0de", state: s.state });
  assert.equal(cb.ok, true);
  assert.equal(h.tokenCalls.length, 1);
  const body = h.tokenCalls[0];
  assert.equal(body.get("client_id"), "Iv1.test");
  assert.equal(body.get("client_secret"), "shh-secret");
  assert.equal(body.get("code"), "c0de");
  assert.equal(body.get("redirect_uri"), REDIRECT);
  assert.equal(body.get("code_verifier"), verifier);
  // The verifier is dropped once used, and the deep link never carries a GitHub token.
  assert.equal(h.store.rows[0].codeVerifier, "");
  assert.ok(!cb.link.includes("gho_web_token"));
  const p = linkParams(cb.link);
  assert.equal(p.get("mode"), "signin");
  assert.equal(p.get("state"), s.state);
  assert.ok((p.get("ticket") ?? "").length >= 40);
  // Replaying the callback (same state) is refused.
  const again = await h.web.callback({ code: "c0de", state: s.state });
  assert.equal(linkParams(again.link).get("error"), "expired");
  assert.equal(h.tokenCalls.length, 1);
});

test("web callback: denied on GitHub, a flow past 10 minutes, and a failed exchange", async () => {
  const h = harness();
  const a = await h.web.start({ mode: "connect", userId: "u1", device: null });
  const denied = linkParams((await h.web.callback({ error: "access_denied", state: a.state })).link);
  assert.equal(denied.get("error"), "access_denied");
  assert.equal(denied.get("mode"), "connect");
  assert.equal(denied.get("state"), a.state);

  const b = await h.web.start({ mode: "signin", userId: null, device: null });
  h.tick(FLOW_TTL_MS + 1);
  assert.equal(linkParams((await h.web.callback({ code: "c", state: b.state })).link).get("error"), "expired");
  assert.equal(h.tokenCalls.length, 0);

  const bad = harness({ tokenAnswer: { error: "bad_verification_code" } });
  const c = await bad.web.start({ mode: "signin", userId: null, device: null });
  const cb = await bad.web.callback({ code: "c", state: c.state });
  assert.equal(linkParams(cb.link).get("error"), "exchange_failed");
  assert.equal(bad.store.rows[0].status, "failed");
  assert.equal(bad.saved.length, 0);
});

test("web sign-in: account resolved at the callback, session handed out once at redeem", async () => {
  const h = harness();
  const s = await h.web.start({ mode: "signin", userId: null, device: "Pixel 9" });
  const ticket = linkParams((await h.web.callback({ code: "c", state: s.state })).link).get("ticket")!;
  assert.equal(h.resolved[0].providerUserId, "583231");
  assert.equal(h.resolved[0].email, "octo@example.com");
  assert.equal(h.resolved[0].emailVerified, true);
  // Connected at once, token encrypted, for the resolved account.
  assert.equal(h.saved.length, 1);
  assert.equal(h.saved[0].userId, "user-new");
  assert.equal(decryptSecret(h.saved[0].accessTokenEnc, h.key), "gho_web_token");
  // Only the hash of the ticket is stored; no session exists before redeem.
  assert.equal(h.store.rows[0].ticketHash, sha256(ticket));
  assert.equal(h.sessions.length, 0);
  assert.equal(await h.web.ticketMode(ticket), "signin");

  const r = await h.web.redeem(ticket, null);
  assert.equal(r.mode, "signin");
  assert.equal(r.mode === "signin" && r.outcome, "created");
  assert.deepEqual(h.sessions, [{ userId: "user-new", device: "Pixel 9" }]);
  await assert.rejects(h.web.redeem(ticket, null), isApp(400, "invalid_ticket"));
  assert.equal(h.sessions.length, 1);
});

test("web ticket: expires after 2 minutes; unknown tickets are refused", async () => {
  const h = harness();
  const s = await h.web.start({ mode: "signin", userId: null, device: null });
  const ticket = linkParams((await h.web.callback({ code: "c", state: s.state })).link).get("ticket")!;
  h.tick(TICKET_TTL_MS + 1);
  await assert.rejects(h.web.redeem(ticket, null), isApp(400, "invalid_ticket"));
  await assert.rejects(h.web.redeem("not-a-real-ticket-at-all-000000", null), isApp(400, "invalid_ticket"));
  assert.equal(h.sessions.length, 0);
});

test("web sign-in: an account conflict comes back as a deep-link error with its code", async () => {
  const h = harness({
    resolve: async () => {
      throw new AppError(409, "email_in_use_link_from_profile", "An account with octo@example.com already exists.");
    },
  });
  const s = await h.web.start({ mode: "signin", userId: null, device: null });
  const cb = await h.web.callback({ code: "c", state: s.state });
  const p = linkParams(cb.link);
  assert.equal(p.get("error"), "email_in_use_link_from_profile");
  assert.match(p.get("message") ?? "", /already exists/);
  assert.equal(p.get("ticket"), null);
  assert.equal(h.saved.length, 0);
});

test("web connect: saved for the starting user; only that user can redeem", async () => {
  const h = harness();
  const s = await h.web.start({ mode: "connect", userId: "user-7", device: null });
  const ticket = linkParams((await h.web.callback({ code: "c", state: s.state })).link).get("ticket")!;
  assert.equal(h.resolved.length, 0);
  assert.equal(h.linked.length, 0);
  assert.equal(h.saved.length, 1);
  assert.equal(h.saved[0].userId, "user-7");
  assert.equal(h.saved[0].login, "octocat");
  assert.deepEqual(h.saved[0].scopes, ["repo", "read:org", "read:user", "user:email"]);
  assert.equal(await h.web.ticketMode(ticket), "connect");
  await assert.rejects(h.web.redeem(ticket, null), isApp(400, "invalid_ticket"));
  await assert.rejects(h.web.redeem(ticket, "user-8"), isApp(400, "invalid_ticket"));
  const r = await h.web.redeem(ticket, "user-7");
  assert.equal(r.mode, "connect");
  assert.equal(r.mode === "connect" && r.connection?.accountLogin, "octocat");
  await assert.rejects(h.web.redeem(ticket, "user-7"), isApp(400, "invalid_ticket"));
  assert.equal(h.sessions.length, 0);
});

test("web link: identity linked to the starting user, connection saved too", async () => {
  const h = harness();
  const s = await h.web.start({ mode: "link", userId: "user-3", device: null });
  const ticket = linkParams((await h.web.callback({ code: "c", state: s.state })).link).get("ticket")!;
  assert.equal(h.linked.length, 1);
  assert.equal(h.linked[0].userId, "user-3");
  assert.equal(h.linked[0].profile.login, "octocat");
  assert.equal(h.saved[0].userId, "user-3");
  const r = await h.web.redeem(ticket, "user-3");
  assert.equal(r.mode, "link");
  assert.equal(r.mode === "link" && r.identity.id, "ident-1");
});

test("callback page: redirects to the deep link, escapes it, and keeps a manual button", () => {
  const html = callbackPage({ ok: false, mode: null, message: "<b>bad</b>", link: `${DEEP_LINK}?error=x&state=a"b` }, "n0nce");
  assert.match(html, /location\.replace/);
  assert.match(html, /RETURN TO SPARKY/);
  assert.ok(html.includes("&lt;b&gt;bad&lt;/b&gt;"));
  assert.ok(html.includes('href="sparky://auth/github?error=x&amp;state=a&quot;b"'));
  assert.ok(!html.includes('a"b'));
  assert.match(html, /nonce="n0nce"/);
});

// ---- the database store: claims and redeems are single conditional writes ----

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

test("prisma store: state claimed once, ticket consumed once, expired ones refused", { skip: dbReady ? false : "database not reachable" }, async () => {
  const stateHash = sha256(`test-${randomUUID()}`);
  const ticketHash = sha256(`ticket-${randomUUID()}`);
  const now = new Date();
  try {
    await prismaWebStore.create({ stateHash, codeVerifier: "v".repeat(64), mode: "signin", userId: null, device: null, expiresAt: new Date(now.getTime() + 60_000) });
    const [a, b] = await Promise.all([prismaWebStore.claim(stateHash, now), prismaWebStore.claim(stateHash, now)]);
    assert.equal([a, b].filter(Boolean).length, 1);
    const row = (a ?? b)!;
    assert.equal(row.status, "exchanging");
    await prismaWebStore.ready(row.id, ticketHash, new Date(now.getTime() + TICKET_TTL_MS), { mode: "signin", userId: randomUUID(), outcome: "created", login: "octo" });
    assert.equal((await prismaWebStore.byTicket(ticketHash))?.codeVerifier, "");
    // Expired, or the wrong kind of caller: not consumed.
    assert.equal(await prismaWebStore.consume(ticketHash, new Date(now.getTime() + TICKET_TTL_MS + 1), null), false);
    assert.equal(await prismaWebStore.consume(ticketHash, now, randomUUID()), false);
    const wins = await Promise.all([prismaWebStore.consume(ticketHash, now, null), prismaWebStore.consume(ticketHash, now, null)]);
    assert.deepEqual(wins.sort(), [false, true]);
  } finally {
    await db().githubOAuthFlow.deleteMany({ where: { stateHash } });
  }
});

test("web start: sign-in asks only who you are; connect asks for repo access", async () => {
  const h = harness();
  const signin = new URL((await h.web.start({ mode: "signin", userId: null, device: null })).authorizeUrl);
  assert.equal(signin.searchParams.get("scope"), "read:user user:email");
  const connect = new URL((await h.web.start({ mode: "connect", userId: "u1", device: null })).authorizeUrl);
  assert.equal(connect.searchParams.get("scope"), GITHUB_SCOPES);
});
