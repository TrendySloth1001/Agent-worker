import { after, test } from "node:test";
import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import type { TokenPayload } from "google-auth-library";
import { ACCESS_TOKEN_URL, DEVICE_CODE_URL, GITHUB_EMAILS_URL, GITHUB_USER_URL, pickGithubEmail, type ConnectionRow } from "../src/connections/deviceFlow.js";
import { decryptSecret, encryptSecret } from "../src/connections/crypto.js";
import { createGithubSso, GITHUB_SSO_SCOPES, type GithubSsoDeps } from "../src/auth/githubSso.js";
import { verifyGoogleIdToken } from "../src/auth/google.js";
import { linkIdentityTx, resolveSsoUser, ssoSignInTx, unlinkIdentity, type SsoProfile } from "../src/auth/sso.js";
import { hashToken } from "../src/auth/jwt.js";
import { login } from "../src/auth/service.js";
import { config } from "../src/config.js";
import { closeDb, db, initDb, onDbUp, tx, type Tx } from "../src/db/prisma.js";
import { AppError } from "../src/util/errors.js";

const isApp = (status: number, code: string) => (e: unknown) => e instanceof AppError && e.status === status && e.code === code;

// ---- GitHub email choice ------------------------------------------------------

test("github email: primary verified wins; noreply addresses are ignored", () => {
  assert.deepEqual(
    pickGithubEmail(
      [
        { email: "1+me@users.noreply.github.com", primary: false, verified: true },
        { email: "other@x.dev", primary: false, verified: true },
        { email: "me@x.dev", primary: true, verified: true },
      ],
      null,
    ),
    { email: "me@x.dev", verified: true },
  );
  // Unverified primary: a verified secondary is still proof.
  assert.deepEqual(
    pickGithubEmail(
      [
        { email: "me@x.dev", primary: true, verified: false },
        { email: "alt@x.dev", primary: false, verified: true },
      ],
      null,
    ),
    { email: "alt@x.dev", verified: true },
  );
  assert.deepEqual(pickGithubEmail([{ email: "me@x.dev", primary: true, verified: false }], null), { email: "me@x.dev", verified: false });
  assert.deepEqual(pickGithubEmail([], "pub@x.dev"), { email: "pub@x.dev", verified: false });
  assert.equal(pickGithubEmail([], null), null);
});

// ---- Google ID token checks -------------------------------------------------------

const AUD = "123-web.apps.googleusercontent.com";
const nowS = () => Math.floor(Date.now() / 1000);
const payload = (over: Partial<TokenPayload> = {}): TokenPayload =>
  ({
    iss: "https://accounts.google.com",
    aud: AUD,
    sub: "1098765",
    email: "Pat@Example.com",
    email_verified: true,
    name: "Pat Doe",
    picture: "https://lh3.googleusercontent.com/a/pat",
    iat: nowS(),
    exp: nowS() + 3600,
    ...over,
  }) as TokenPayload;
const verifier = (p: TokenPayload | Error) => async (_t: string, audience: string) => {
  assert.equal(audience, AUD);
  if (p instanceof Error) throw p;
  return p;
};

test("google: a valid token becomes a profile", async () => {
  const p = await verifyGoogleIdToken("tok", { clientId: AUD, verify: verifier(payload()) });
  assert.deepEqual(p, {
    provider: "google",
    providerUserId: "1098765",
    email: "Pat@Example.com",
    emailVerified: true,
    name: "Pat Doe",
    avatarUrl: "https://lh3.googleusercontent.com/a/pat",
    login: null,
  });
  // Both issuer spellings are Google's.
  await verifyGoogleIdToken("tok", { clientId: AUD, verify: verifier(payload({ iss: "accounts.google.com" })) });
});

test("google: not configured, bad signature, wrong audience/issuer, expired are refused", async () => {
  await assert.rejects(verifyGoogleIdToken("tok", { clientId: undefined, verify: verifier(payload()) }), isApp(503, "google_not_configured"));
  const bad = isApp(401, "invalid_google_token");
  await assert.rejects(verifyGoogleIdToken("tok", { clientId: AUD, verify: verifier(new Error("Invalid token signature")) }), bad);
  await assert.rejects(verifyGoogleIdToken("tok", { clientId: AUD, verify: async () => payload({ aud: "someone-else" }) }), bad);
  await assert.rejects(verifyGoogleIdToken("tok", { clientId: AUD, verify: verifier(payload({ iss: "https://evil.example" })) }), bad);
  await assert.rejects(verifyGoogleIdToken("tok", { clientId: AUD, verify: verifier(payload({ exp: nowS() - 3600 })) }), bad);
  await assert.rejects(verifyGoogleIdToken("tok", { clientId: AUD, verify: verifier(payload({ sub: "" })) }), bad);
});

test("google: an unverified email is reported as unverified", async () => {
  const p = await verifyGoogleIdToken("tok", { clientId: AUD, verify: verifier(payload({ email_verified: false })) });
  assert.equal(p.emailVerified, false);
});

// ---- GitHub sign-in over the device flow (scripted GitHub) ---------------------------

function ghHarness(tokenAnswers: object[], opts: { emails?: object[]; signIn?: GithubSsoDeps["signIn"] } = {}) {
  let now = 1_000_000;
  const key = randomBytes(32);
  const calls: { url: string; body?: string }[] = [];
  const saved: ConnectionRow[] = [];
  const profiles: { profile: SsoProfile; device: string | null; linkTo?: string }[] = [];
  const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
    new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...headers } });
  const fakeFetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, body: typeof init?.body === "string" ? init.body : undefined });
    if (url === DEVICE_CODE_URL) {
      return json({ device_code: "dev-9", user_code: "WXYZ-0001", verification_uri: "https://github.com/login/device", expires_in: 900, interval: 5 });
    }
    if (url === ACCESS_TOKEN_URL) return json(tokenAnswers.shift() ?? { error: "authorization_pending" });
    if (url === GITHUB_USER_URL) {
      assert.equal((init?.headers as Record<string, string>).Authorization, "Bearer gho_sso_token");
      return json({ login: "octocat", id: 583231, name: "The Octocat", email: null, avatar_url: "https://avatars.example/octocat" });
    }
    if (url === GITHUB_EMAILS_URL) {
      return json(opts.emails ?? [{ email: "octo@example.com", primary: true, verified: true }]);
    }
    throw new Error(`unexpected fetch ${url}`);
  }) as typeof fetch;
  const user = { id: "user-1", role: "user" } as never;
  const flows = createGithubSso({
    clientId: () => "Iv1.test",
    fetch: fakeFetch,
    now: () => now,
    signIn:
      opts.signIn ??
      (async (profile, device) => {
        profiles.push({ profile, device });
        return { user, outcome: "created", tokens: { accessToken: "a", accessExpiresAt: "", refreshToken: "r", refreshExpiresAt: "", sessionId: "s" } };
      }),
    link: async (userId, profile) => {
      profiles.push({ profile, device: null, linkTo: userId });
      return { id: "ident-1", provider: "github", email: profile.email, login: profile.login, createdAt: "" };
    },
    encrypt: (plain) => encryptSecret(plain, key),
    saveConnection: async (row) => {
      saved.push(row);
    },
  });
  return {
    flows,
    calls,
    saved,
    profiles,
    key,
    tick: (s: number) => {
      now += s * 1000;
    },
  };
}

test("github sso: asks for sign-in + connection scopes", async () => {
  const h = ghHarness([]);
  await h.flows.start(null, { device: "Pixel" });
  assert.equal(new URLSearchParams(h.calls[0].body).get("scope"), GITHUB_SSO_SCOPES);
  assert.equal(GITHUB_SSO_SCOPES, "read:user user:email");
});

test("github sso: pending, slow_down (reported once), then a session; the result is handed out once", async () => {
  const h = ghHarness([{ error: "authorization_pending" }, { error: "slow_down", interval: 10 }, { access_token: "gho_sso_token", scope: "repo,read:org,read:user,user:email" }]);
  const { flowId } = await h.flows.start(null, { device: "Pixel" });
  h.tick(5);
  assert.equal((await h.flows.poll(null, flowId)).status, "pending");
  h.tick(5);
  const slow = await h.flows.poll(null, flowId);
  assert.equal(slow.status, "slow_down");
  assert.equal(slow.interval, 10);
  assert.equal((await h.flows.poll(null, flowId)).status, "pending");
  h.tick(10);
  const done = await h.flows.poll(null, flowId);
  assert.equal(done.status, "done");
  assert.equal(done.result?.kind, "session");
  assert.ok(!JSON.stringify(done).includes("gho_sso_token"));
  // The profile: GitHub id, primary verified email, name, login.
  assert.deepEqual(h.profiles[0], {
    device: "Pixel",
    profile: {
      provider: "github",
      providerUserId: "583231",
      email: "octo@example.com",
      emailVerified: true,
      name: "The Octocat",
      avatarUrl: "https://avatars.example/octocat",
      login: "octocat",
    },
  });
  // Connected at once, token encrypted, owned by the signed-in user.
  assert.equal(h.saved.length, 1);
  assert.equal(h.saved[0].userId, "user-1");
  assert.equal(decryptSecret(h.saved[0].accessTokenEnc, h.key), "gho_sso_token");
  assert.deepEqual(h.saved[0].scopes, ["repo", "read:org", "read:user", "user:email"]);
  // A session is never handed out twice.
  await assert.rejects(h.flows.poll(null, flowId), isApp(404, "not_found"));
});

test("github sso: an account conflict comes back as an error with its code", async () => {
  const h = ghHarness([{ access_token: "gho_sso_token" }], {
    signIn: async () => {
      throw new AppError(409, "email_in_use_link_from_profile", "An account with octo@example.com already exists.");
    },
  });
  const { flowId } = await h.flows.start(null, { device: null });
  h.tick(5);
  const r = await h.flows.poll(null, flowId);
  assert.equal(r.status, "error");
  assert.equal(r.errorCode, "email_in_use_link_from_profile");
  assert.equal(r.errorStatus, 409);
  assert.equal(h.saved.length, 0);
});

test("github sso: signed-out flows don't replace each other; link flows are private to their user", async () => {
  const h = ghHarness([{ access_token: "gho_sso_token", scope: "repo,read:user" }]);
  const a = await h.flows.start(null, { device: null });
  const b = await h.flows.start(null, { device: null });
  assert.equal((await h.flows.poll(null, a.flowId)).status, "pending");
  assert.equal((await h.flows.poll(null, b.flowId)).status, "pending");

  const link = await h.flows.start("user-7", { device: null });
  await assert.rejects(h.flows.poll(null, link.flowId), isApp(404, "not_found"));
  await assert.rejects(h.flows.poll("user-8", link.flowId), isApp(404, "not_found"));
  h.tick(5);
  const r = await h.flows.poll("user-7", link.flowId);
  assert.equal(r.status, "done");
  assert.equal(r.result?.kind, "linked");
  assert.equal(h.profiles.at(-1)?.linkTo, "user-7");
  assert.equal(h.saved.at(-1)?.userId, "user-7");
});

test("github sso: no readable email is a clear error", async () => {
  // The real resolver refuses a profile without email; here only the profile is checked.
  const h = ghHarness([{ access_token: "gho_sso_token" }], { emails: [] });
  const { flowId } = await h.flows.start(null, { device: null });
  h.tick(5);
  await h.flows.poll(null, flowId);
  assert.equal(h.profiles[0].profile.email, null);
});

// ---- account resolution against the database (rolled back) ------------------------------

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
/** Runs [fn] in a transaction that is always rolled back: no rows are left behind. */
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

const tag = () => randomUUID().slice(0, 8);
const testEmail = (t: string) => `sso-test-${t}@example.test`;
const googleProfile = (t: string, over: Partial<SsoProfile> = {}): SsoProfile => ({
  provider: "google",
  providerUserId: `g-${t}`,
  email: testEmail(t),
  emailVerified: true,
  name: "Test Person",
  avatarUrl: "https://lh3.googleusercontent.com/a/x",
  login: null,
  ...over,
});
const passwordUser = (c: Tx, email: string) => c.user.create({ data: { email, passwordHash: "argon2-placeholder", name: "Has Password" } });

test("resolve: a valid Google profile creates a passwordless account, then signs in to it", needsDb, async () => {
  await rolledBack(async (c) => {
    const t = tag();
    const p = googleProfile(t);
    const first = await resolveSsoUser(c, p);
    assert.equal(first.outcome, "created");
    assert.equal(first.user.email, testEmail(t));
    assert.equal(first.user.passwordHash, null);
    assert.equal(first.user.name, "Test Person");
    assert.equal(first.user.avatarUrl, "https://lh3.googleusercontent.com/a/x");
    assert.equal(first.user.role, "user");
    const ident = await c.authIdentity.findMany({ where: { userId: first.user.id } });
    assert.equal(ident.length, 1);
    assert.equal(ident[0].provider, "google");
    assert.equal(ident[0].emailVerified, true);

    const again = await resolveSsoUser(c, p);
    assert.equal(again.outcome, "signed_in");
    assert.equal(again.user.id, first.user.id);
  });
});

test("resolve: same verified email as a password account links to it", needsDb, async () => {
  await rolledBack(async (c) => {
    const t = tag();
    const existing = await passwordUser(c, testEmail(t));
    // Provider emails compare case-insensitively.
    const r = await resolveSsoUser(c, googleProfile(t, { email: testEmail(t).toUpperCase() }));
    assert.equal(r.outcome, "linked");
    assert.equal(r.user.id, existing.id);
    assert.equal(await c.authIdentity.count({ where: { userId: existing.id, provider: "google" } }), 1);
    // A GitHub identity with the same verified email links too.
    const g = await resolveSsoUser(c, { ...googleProfile(t), provider: "github", providerUserId: `gh-${t}`, login: "octo" });
    assert.equal(g.outcome, "linked");
    assert.equal(g.user.id, existing.id);
  });
});

test("resolve: an unverified email never links (409), and creates an account only when the email is free", needsDb, async () => {
  await rolledBack(async (c) => {
    const t = tag();
    const existing = await passwordUser(c, testEmail(t));
    await assert.rejects(resolveSsoUser(c, googleProfile(t, { emailVerified: false })), isApp(409, "email_in_use_link_from_profile"));
    assert.equal(await c.authIdentity.count({ where: { userId: existing.id } }), 0);

    const t2 = tag();
    const fresh = await resolveSsoUser(c, googleProfile(t2, { emailVerified: false }));
    assert.equal(fresh.outcome, "created");
    assert.notEqual(fresh.user.id, existing.id);
    assert.equal(fresh.user.role, "user");
  });
});

test("resolve: an account squatted with an unverified email is not taken over by a verified sign-in", needsDb, async () => {
  await rolledBack(async (c) => {
    const t = tag();
    const squat = await resolveSsoUser(c, { ...googleProfile(t), provider: "github", providerUserId: `gh-${t}`, emailVerified: false, login: "squatter" });
    assert.equal(squat.outcome, "created");
    await assert.rejects(resolveSsoUser(c, googleProfile(t)), isApp(409, "email_in_use_link_from_profile"));
  });
});

test("resolve: OWNER_EMAIL becomes the owner only with a verified email", needsDb, async (t) => {
  const ownerEmail = config.auth.ownerEmail;
  if (!ownerEmail) return t.skip("OWNER_EMAIL not set");
  for (const verified of [false, true]) {
    await rolledBack(async (c) => {
      // Inside the rolled-back transaction: no owner, and the address is free.
      await c.user.updateMany({ where: { role: "owner" }, data: { role: "user" } });
      await c.user.updateMany({ where: { email: ownerEmail }, data: { email: `moved-${tag()}@example.test` } });
      const r = await resolveSsoUser(c, googleProfile(tag(), { email: ownerEmail, emailVerified: verified }));
      assert.equal(r.outcome, "created");
      assert.equal(r.user.role, verified ? "owner" : "user");
    });
  }
});

test("resolve: a profile without email is refused", needsDb, async () => {
  await rolledBack(async (c) => {
    await assert.rejects(resolveSsoUser(c, googleProfile(tag(), { email: null })), isApp(400, "no_email"));
  });
});

test("sign-in issues a session (refresh token stored hashed)", needsDb, async () => {
  await rolledBack(async (c) => {
    const { user, tokens, outcome } = await ssoSignInTx(c, googleProfile(tag()), "Test device");
    assert.equal(outcome, "created");
    assert.ok(tokens.accessToken.split(".").length === 3);
    const row = await c.authSession.findUnique({ where: { tokenHash: hashToken(tokens.refreshToken) } });
    assert.equal(row?.userId, user.id);
    assert.equal(row?.device, "Test device");
    assert.ok(user.lastLoginAt);
  });
});

test("link from profile: idempotent for the same user, refused when another account has it", needsDb, async () => {
  await rolledBack(async (c) => {
    const t = tag();
    const a = await passwordUser(c, testEmail(`${t}a`));
    const b = await passwordUser(c, testEmail(`${t}b`));
    const p = googleProfile(t, { emailVerified: false });
    const first = await linkIdentityTx(c, a.id, p);
    assert.equal(first.provider, "google");
    assert.equal((await linkIdentityTx(c, a.id, p)).id, first.id);
    await assert.rejects(linkIdentityTx(c, b.id, p), isApp(409, "identity_in_use"));
  });
});

test("passwordless account: password login says how to sign in; the last method cannot be unlinked", needsDb, async () => {
  // These paths run their own queries, so this one throwaway user is committed and then deleted.
  const t = tag();
  const { user } = await tx((c) => resolveSsoUser(c, googleProfile(t)));
  try {
    await assert.rejects(login(testEmail(t), "whatever-password", null), (e: unknown) => {
      assert.ok(e instanceof AppError && e.code === "password_not_set");
      assert.match(e.message, /Continue with Google/);
      return true;
    });
    const ident = await db().authIdentity.findFirstOrThrow({ where: { userId: user.id } });
    await assert.rejects(unlinkIdentity(user.id, ident.id), isApp(409, "last_sign_in_method"));
    // With a password set, unlinking is fine.
    await db().user.update({ where: { id: user.id }, data: { passwordHash: "argon2-placeholder" } });
    await unlinkIdentity(user.id, ident.id);
    assert.equal(await db().authIdentity.count({ where: { userId: user.id } }), 0);
  } finally {
    await db().user.deleteMany({ where: { id: user.id } });
  }
});

test("missingGithubScopes: what a reconnect would add", async () => {
  const { missingGithubScopes } = await import("../src/connections/deviceFlow.js");
  assert.deepEqual(missingGithubScopes([]), []);
  assert.deepEqual(missingGithubScopes(["repo", "read:user", "read:org"]), ["user:email", "workflow", "notifications"]);
  assert.deepEqual(missingGithubScopes(["repo", "user", "admin:org", "workflow", "notifications"]), []);
});

test("github sso: a sign-in-only grant does not become a connection", async () => {
  const h = ghHarness([{ access_token: "gho_sso_token", scope: "read:user,user:email" }]);
  const { flowId } = await h.flows.start(null, { device: null });
  h.tick(5);
  const r = await h.flows.poll(null, flowId);
  assert.equal(r.status, "done");
  assert.equal(r.result?.kind, "session");
  assert.equal(h.saved.length, 0);
});
