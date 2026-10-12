import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { sha256, pkceChallenge } from "../src/auth/githubWeb.js";
import { callbackPage } from "../src/auth/githubWebPage.js";
import { createOAuthFlow, CONNECT_DEEP_LINK, type FlowRow, type FlowStore } from "../src/connections/oauth/flow.js";
import { googleDrive, notion, GOOGLE_DRIVE_SCOPE, GOOGLE_REVOKE_URL, GOOGLE_USERINFO_URL, type OAuthProvider, type ProviderId } from "../src/connections/oauth/providers.js";
import { createTokenManager, providerFetch, REFRESH_EARLY_MS, type ConnectionRepo, type StoredConnection } from "../src/connections/oauth/tokens.js";
import { blocksToMarkdown, markdownToBlocks, RICH_MAX, type NotionBlock } from "../src/connections/oauth/notionMarkdown.js";
import { createDrive, exportMime, readKind, GDOC, GSHEET } from "../src/connections/oauth/drive.js";
import { createNotion, checkNotionId } from "../src/connections/oauth/notion.js";
import { appsGround, appsIntent, type AppTools } from "../src/connections/oauth/tools.js";
import { createPicker, pickerPage, projectNumber } from "../src/connections/oauth/picker.js";
import { AppError } from "../src/util/errors.js";

const CLIENT = "123456789012-abc.apps.googleusercontent.com";
const providers: Record<ProviderId, OAuthProvider> = {
  google_drive: { ...googleDrive, clientId: () => CLIENT, clientSecret: () => "g-secret" },
  notion: { ...notion, clientId: () => "notion-id", clientSecret: () => "notion-secret" },
};
const redirect = (p: ProviderId) => `https://sparky.example/connect/${p}/callback`;
const isApp = (status: number, code: string) => (e: unknown) => e instanceof AppError && e.status === status && e.code === code;
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function memoryFlows(connected = new Set<string>()): FlowStore & { rows: FlowRow[] } {
  const rows: FlowRow[] = [];
  return {
    rows,
    async create(r) {
      rows.push({ ...r, id: randomUUID(), status: "pending", ticketHash: null, ticketExpiresAt: null, result: null });
    },
    async claim(provider, mode, h, now) {
      const r = rows.find((x) => x.stateHash === h && x.provider === provider && x.mode === mode && x.status === "pending" && x.expiresAt > now);
      if (!r) return null;
      r.status = "exchanging";
      return { ...r };
    },
    async peek(provider, mode, h, now) {
      const r = rows.find((x) => x.stateHash === h && x.provider === provider && x.mode === mode && x.status === "pending" && x.expiresAt > now);
      return r ? { ...r } : null;
    },
    async ready(id, ticketHash, ticketExpiresAt, result) {
      Object.assign(rows.find((x) => x.id === id)!, { status: "ready", ticketHash, ticketExpiresAt, result, codeVerifier: "" });
    },
    async fail(id) {
      Object.assign(rows.find((x) => x.id === id)!, { status: "failed", codeVerifier: "" });
    },
    async consume(provider, h, now, userId) {
      const r = rows.find((x) => x.ticketHash === h && x.provider === provider && x.userId === userId && x.status === "ready" && x.ticketExpiresAt! > now);
      if (!r) return null;
      r.status = "redeemed";
      return { ...r };
    },
    async hasConnection(userId, provider) {
      return connected.has(`${userId}:${provider}`);
    },
    async purge() {},
  };
}

type Call = { url: string; init: RequestInit };
function mockFetch(handler: (url: string, init: RequestInit) => Response | Promise<Response>) {
  const calls: Call[] = [];
  const f = (async (input: string | URL | Request, init: RequestInit = {}) => {
    const url = String(input);
    calls.push({ url, init });
    return handler(url, init);
  }) as typeof fetch;
  return { f, calls };
}

// ---- OAuth web flow -------------------------------------------------------------

test("google drive start: drive.file + openid, PKCE, offline, consent on first connect", async () => {
  const store = memoryFlows();
  const flow = createOAuthFlow({ fetch, now: Date.now, store, redirectUri: redirect, save: async () => {}, providers });
  const s = await flow.start("google_drive", "u1");
  const u = new URL(s.authorizeUrl);
  assert.equal(u.origin + u.pathname, "https://accounts.google.com/o/oauth2/v2/auth");
  const scopes = u.searchParams.get("scope")!.split(" ");
  assert.deepEqual(scopes.sort(), ["email", "openid", "profile", GOOGLE_DRIVE_SCOPE].sort());
  assert.ok(!u.searchParams.get("scope")!.includes("drive.readonly"));
  assert.equal(u.searchParams.get("access_type"), "offline");
  assert.equal(u.searchParams.get("prompt"), "consent");
  assert.equal(u.searchParams.get("include_granted_scopes"), "true");
  assert.equal(u.searchParams.get("redirect_uri"), redirect("google_drive"));
  assert.equal(u.searchParams.get("code_challenge_method"), "S256");
  assert.equal(u.searchParams.get("code_challenge"), pkceChallenge(store.rows[0].codeVerifier));
  // The state is stored hashed only.
  assert.equal(store.rows[0].stateHash, sha256(s.state));
  assert.ok(!JSON.stringify(store.rows).includes(s.state));
});

test("google drive start: an existing connection is not forced through consent", async () => {
  const flow = createOAuthFlow({ fetch, now: Date.now, store: memoryFlows(new Set(["u1:google_drive"])), redirectUri: redirect, save: async () => {}, providers });
  const u = new URL((await flow.start("google_drive", "u1")).authorizeUrl);
  assert.equal(u.searchParams.get("prompt"), "select_account");
});

test("notion start: owner=user, no PKCE, no scope", async () => {
  const flow = createOAuthFlow({ fetch, now: Date.now, store: memoryFlows(), redirectUri: redirect, save: async () => {}, providers });
  const u = new URL((await flow.start("notion", "u1")).authorizeUrl);
  assert.equal(u.origin + u.pathname, "https://api.notion.com/v1/oauth/authorize");
  assert.equal(u.searchParams.get("owner"), "user");
  assert.equal(u.searchParams.get("response_type"), "code");
  assert.equal(u.searchParams.get("code_challenge"), null);
  assert.equal(u.searchParams.get("scope"), null);
});

test("start without client credentials: not configured", async () => {
  const off = { ...providers, notion: { ...providers.notion, clientId: () => undefined } };
  const flow = createOAuthFlow({ fetch, now: Date.now, store: memoryFlows(), redirectUri: redirect, save: async () => {}, providers: off });
  await assert.rejects(flow.start("notion", "u1"), isApp(503, "connector_not_configured"));
});

test("google callback: code + verifier exchanged, profile saved, one-time ticket deep link", async () => {
  const store = memoryFlows();
  const saved: unknown[] = [];
  const { f, calls } = mockFetch((url) => {
    if (url === googleDrive.tokenUrl) return json({ access_token: "at-1", refresh_token: "rt-1", expires_in: 3599, scope: `openid ${GOOGLE_DRIVE_SCOPE}` });
    if (url === GOOGLE_USERINFO_URL) return json({ sub: "g-42", email: "nick@example.com", name: "Nick Rivera", picture: "https://lh3.example/p.png" });
    return json({}, 404);
  });
  const flow = createOAuthFlow({ fetch: f, now: Date.now, store, redirectUri: redirect, save: async (...a) => void saved.push(a), providers });
  const s = await flow.start("google_drive", "u1");
  const verifier = store.rows[0].codeVerifier;
  const cb = await flow.callback("google_drive", { code: "the-code", state: s.state });
  assert.equal(cb.ok, true);
  const link = new URL(cb.link);
  assert.ok(cb.link.startsWith(CONNECT_DEEP_LINK));
  assert.equal(link.searchParams.get("provider"), "google_drive");
  assert.equal(link.searchParams.get("state"), s.state);
  const ticket = link.searchParams.get("ticket")!;
  assert.ok(ticket.length > 20);
  // No token in the link.
  assert.ok(!cb.link.includes("at-1") && !cb.link.includes("rt-1"));
  const body = new URLSearchParams(String(calls[0].init.body));
  assert.equal(body.get("code"), "the-code");
  assert.equal(body.get("code_verifier"), verifier);
  assert.equal(body.get("grant_type"), "authorization_code");
  assert.equal(body.get("client_secret"), "g-secret");
  const [userId, provider, grant, profile] = saved[0] as [string, string, { refreshToken: string }, { email: string; name: string }];
  assert.equal(userId, "u1");
  assert.equal(provider, "google_drive");
  assert.equal(grant.refreshToken, "rt-1");
  assert.equal(profile.email, "nick@example.com");
  assert.equal(profile.name, "Nick Rivera");
  // The verifier is cleared once used.
  assert.equal(store.rows[0].codeVerifier, "");

  // The ticket works once, for the user who started the flow.
  await assert.rejects(flow.redeem("google_drive", ticket, "someone-else"), isApp(400, "invalid_ticket"));
  const row = await flow.redeem("google_drive", ticket, "u1");
  assert.equal(row.userId, "u1");
  await assert.rejects(flow.redeem("google_drive", ticket, "u1"), isApp(400, "invalid_ticket"));
  // A replayed callback finds no pending flow.
  const again = await flow.callback("google_drive", { code: "the-code", state: s.state });
  assert.equal(again.ok, false);
  assert.equal(new URL(again.link).searchParams.get("error"), "expired");
});

test("notion callback: Basic auth JSON exchange, workspace kept as meta", async () => {
  const store = memoryFlows();
  const saved: Array<[string, string, unknown, { meta: Record<string, unknown>; login: string }]> = [];
  const { f, calls } = mockFetch(() =>
    json({
      access_token: "secret_n",
      refresh_token: "nrt-1",
      expires_in: 3600,
      bot_id: "bot-1",
      workspace_id: "ws-1",
      workspace_name: "Nick's Notion",
      workspace_icon: "🦊",
      owner: { type: "user", user: { id: "nu-1", name: "Nick", avatar_url: null, person: { email: "nick@example.com" } } },
    }),
  );
  const flow = createOAuthFlow({ fetch: f, now: Date.now, store, redirectUri: redirect, save: async (...a) => void saved.push(a as never), providers });
  const s = await flow.start("notion", "u1");
  const cb = await flow.callback("notion", { code: "c", state: s.state });
  assert.equal(cb.ok, true);
  const init = calls[0].init;
  assert.equal(new Headers(init.headers).get("Authorization"), `Basic ${Buffer.from("notion-id:notion-secret").toString("base64")}`);
  assert.deepEqual(JSON.parse(String(init.body)), { grant_type: "authorization_code", code: "c", redirect_uri: redirect("notion") });
  assert.equal(saved[0][3].login, "nick@example.com");
  assert.equal(saved[0][3].meta.workspaceName, "Nick's Notion");
  assert.equal(saved[0][3].meta.workspaceIcon, "🦊");
});

test("callback: denied, missing state, failed exchange all deep-link an error", async () => {
  const store = memoryFlows();
  const { f } = mockFetch(() => json({ error: "invalid_grant" }, 400));
  const flow = createOAuthFlow({ fetch: f, now: Date.now, store, redirectUri: redirect, save: async () => {}, providers });
  assert.equal(new URL((await flow.callback("notion", {})).link).searchParams.get("error"), "bad_request");
  const s1 = await flow.start("notion", "u1");
  const denied = await flow.callback("notion", { state: s1.state, error: "access_denied" });
  assert.equal(new URL(denied.link).searchParams.get("error"), "access_denied");
  assert.match(denied.message, /denied on Notion/);
  const s2 = await flow.start("notion", "u1");
  const bad = await flow.callback("notion", { state: s2.state, code: "x" });
  assert.equal(bad.ok, false);
  assert.equal(new URL(bad.link).searchParams.get("error"), "exchange_failed");
  // A state of another provider does not match.
  const s3 = await flow.start("google_drive", "u1");
  assert.equal(new URL((await flow.callback("notion", { state: s3.state, code: "x" })).link).searchParams.get("error"), "expired");
});

test("callback page names the connector and escapes the message", () => {
  const html = callbackPage({ ok: false, link: "sparky://auth/connect?error=x", message: "<b>nope</b>" }, "n0nce", { name: "Notion", mark: "notion", stopped: "Notion connection stopped" });
  assert.match(html, /sparky · notion/);
  assert.match(html, /Notion connection stopped/);
  assert.ok(html.includes("&lt;b&gt;nope&lt;/b&gt;"));
});

// ---- tokens: refresh, rotation, revoke --------------------------------------------

function memoryRepo(initial: Partial<StoredConnection> & { refreshTokenEnc?: string | null }) {
  const rows = new Map<string, StoredConnection>();
  rows.set("u1:notion", { accessTokenEnc: "enc:old-at", refreshTokenEnc: "enc:old-rt", expiresAt: null, needsReauth: false, accountLogin: "x", ...initial });
  let swaps = 0;
  const repo: ConnectionRepo & { rows: typeof rows; swaps: () => number } = {
    rows,
    swaps: () => swaps,
    async get(u, p) {
      const r = rows.get(`${u}:${p}`);
      return r ? { ...r } : null;
    },
    async upsert(u, p, d) {
      const prev = rows.get(`${u}:${p}`);
      rows.set(`${u}:${p}`, {
        accessTokenEnc: d.accessTokenEnc,
        refreshTokenEnc: d.refreshTokenEnc ?? (d.keepRefreshIfNull ? (prev?.refreshTokenEnc ?? null) : null),
        expiresAt: d.expiresAt,
        needsReauth: false,
        accountLogin: d.profile.login,
      });
    },
    async swapTokens(u, p, expect, d) {
      const r = rows.get(`${u}:${p}`);
      if (!r || r.refreshTokenEnc !== expect) return false;
      swaps++;
      Object.assign(r, d);
      return true;
    },
    async flagReauth(u, p) {
      const r = rows.get(`${u}:${p}`);
      if (r) r.needsReauth = true;
    },
    async touch() {},
    async remove(u, p) {
      return rows.delete(`${u}:${p}`);
    },
  };
  return repo;
}
const enc = (s: string) => `enc:${s}`;
const dec = (s: string) => s.replace(/^enc:/, "");

test("a token far from expiry is used as is", async () => {
  const repo = memoryRepo({ expiresAt: new Date(Date.now() + 3600_000) });
  const { f, calls } = mockFetch(() => json({}));
  const t = createTokenManager({ repo, fetch: f, now: Date.now, encrypt: enc, decrypt: dec, providers });
  assert.equal(await t.accessToken("u1", "notion"), "old-at");
  assert.equal(calls.length, 0);
});

test("refresh before expiry rotates the refresh token atomically, one refresh for concurrent callers", async () => {
  const repo = memoryRepo({ expiresAt: new Date(Date.now() + REFRESH_EARLY_MS / 2) });
  const { f, calls } = mockFetch(async () => {
    await new Promise((r) => setTimeout(r, 10));
    return json({ access_token: "new-at", refresh_token: "new-rt", expires_in: 3600 });
  });
  const t = createTokenManager({ repo, fetch: f, now: Date.now, encrypt: enc, decrypt: dec, providers });
  const [a, b] = await Promise.all([t.accessToken("u1", "notion"), t.accessToken("u1", "notion")]);
  assert.equal(a, "new-at");
  assert.equal(b, "new-at");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, notion.tokenUrl);
  assert.deepEqual(JSON.parse(String(calls[0].init.body)), { grant_type: "refresh_token", refresh_token: "old-rt" });
  const row = repo.rows.get("u1:notion")!;
  assert.equal(row.refreshTokenEnc, "enc:new-rt");
  assert.equal(row.accessTokenEnc, "enc:new-at");
  assert.ok(row.expiresAt!.getTime() > Date.now() + 3000_000);
});

test("a lost rotation race reads the winner's token instead of overwriting it", async () => {
  const repo = memoryRepo({ expiresAt: new Date(Date.now() + 1000) });
  const { f } = mockFetch(() => {
    // Another instance rotates while this refresh is in flight.
    Object.assign(repo.rows.get("u1:notion")!, { refreshTokenEnc: "enc:other-rt", accessTokenEnc: "enc:other-at" });
    return json({ access_token: "mine-at", refresh_token: "mine-rt", expires_in: 3600 });
  });
  const t = createTokenManager({ repo, fetch: f, now: Date.now, encrypt: enc, decrypt: dec, providers });
  assert.equal(await t.accessToken("u1", "notion"), "other-at");
  assert.equal(repo.rows.get("u1:notion")!.refreshTokenEnc, "enc:other-rt");
});

test("google refresh without a new refresh token keeps the old one", async () => {
  const repo = memoryRepo({});
  repo.rows.set("u1:google_drive", { accessTokenEnc: "enc:at", refreshTokenEnc: "enc:rt", expiresAt: new Date(Date.now() - 1000), needsReauth: false, accountLogin: "x" });
  const { f, calls } = mockFetch(() => json({ access_token: "at2", expires_in: 3599 }));
  const t = createTokenManager({ repo, fetch: f, now: Date.now, encrypt: enc, decrypt: dec, providers });
  assert.equal(await t.accessToken("u1", "google_drive"), "at2");
  const body = new URLSearchParams(String(calls[0].init.body));
  assert.equal(body.get("grant_type"), "refresh_token");
  assert.equal(body.get("refresh_token"), "rt");
  assert.equal(body.get("client_id"), CLIENT);
  assert.equal(repo.rows.get("u1:google_drive")!.refreshTokenEnc, "enc:rt");
});

test("a rejected refresh flags the connection for Reconnect", async () => {
  const repo = memoryRepo({ expiresAt: new Date(Date.now() - 1000) });
  const { f } = mockFetch(() => json({ error: "invalid_grant" }, 400));
  const t = createTokenManager({ repo, fetch: f, now: Date.now, encrypt: enc, decrypt: dec, providers });
  await assert.rejects(t.accessToken("u1", "notion"), isApp(401, "connector_reauth"));
  assert.equal(repo.rows.get("u1:notion")!.needsReauth, true);
  // Flagged: no more provider calls until Reconnect.
  await assert.rejects(t.accessToken("u1", "notion"), isApp(401, "connector_reauth"));
});

test("a network failure keeps using an access token that has not expired yet", async () => {
  const repo = memoryRepo({ expiresAt: new Date(Date.now() + 60_000) });
  const f = (async () => {
    throw new Error("ECONNRESET");
  }) as typeof fetch;
  const t = createTokenManager({ repo, fetch: f, now: Date.now, encrypt: enc, decrypt: dec, providers });
  assert.equal(await t.accessToken("u1", "notion"), "old-at");
});

test("not connected is a 404 the app can show", async () => {
  const t = createTokenManager({ repo: memoryRepo({}), fetch, now: Date.now, encrypt: enc, decrypt: dec, providers });
  await assert.rejects(t.accessToken("u2", "google_drive"), isApp(404, "connector_not_connected"));
});

test("disconnect revokes at Google with the refresh token, then deletes", async () => {
  const repo = memoryRepo({});
  repo.rows.set("u1:google_drive", { accessTokenEnc: "enc:at", refreshTokenEnc: "enc:rt", expiresAt: null, needsReauth: false, accountLogin: "x" });
  const { f, calls } = mockFetch(() => new Response("", { status: 200 }));
  const t = createTokenManager({ repo, fetch: f, now: Date.now, encrypt: enc, decrypt: dec, providers });
  assert.deepEqual(await t.disconnect("u1", "google_drive"), { deleted: true, revoked: true });
  assert.equal(calls[0].url, GOOGLE_REVOKE_URL);
  assert.equal(new URLSearchParams(String(calls[0].init.body)).get("token"), "rt");
  assert.equal(repo.rows.has("u1:google_drive"), false);
  assert.deepEqual(await t.disconnect("u1", "google_drive"), { deleted: false, revoked: false });
});

test("disconnect still deletes when the provider revoke fails", async () => {
  const repo = memoryRepo({});
  const f = (async () => {
    throw new Error("down");
  }) as typeof fetch;
  const t = createTokenManager({ repo, fetch: f, now: Date.now, encrypt: enc, decrypt: dec, providers });
  assert.deepEqual(await t.disconnect("u1", "notion"), { deleted: true, revoked: false });
});

test("providerFetch: 401 flags Reconnect, 429 is a retryable rate limit", async () => {
  const repo = memoryRepo({});
  const t = createTokenManager({ repo, fetch, now: Date.now, encrypt: enc, decrypt: dec, providers });
  const f401 = mockFetch(() => json({}, 401)).f;
  await assert.rejects(providerFetch("u1", "notion", "https://api.notion.com/v1/search", {}, t, f401), isApp(401, "connector_reauth"));
  assert.equal(repo.rows.get("u1:notion")!.needsReauth, true);
  repo.rows.get("u1:notion")!.needsReauth = false;
  const f429 = mockFetch(() => json({}, 429)).f;
  await assert.rejects(providerFetch("u1", "notion", "https://api.notion.com/v1/search", {}, t, f429), (e) => e instanceof AppError && e.status === 429 && e.retryable);
  const ok = mockFetch((_u, init) => json({ auth: new Headers(init.headers).get("Authorization") })).f;
  const res = await providerFetch("u1", "notion", "https://api.notion.com/v1/search", {}, t, ok);
  assert.deepEqual(await res.json(), { auth: "Bearer old-at" });
});

// ---- Notion markdown --------------------------------------------------------------

const rt = (text: string, ann: Record<string, boolean> = {}, href: string | null = null) => ({ type: "text", plain_text: text, href, annotations: ann });

test("notion blocks become markdown", () => {
  const blocks: NotionBlock[] = [
    { type: "heading_1", heading_1: { rich_text: [rt("Plan")] } },
    { type: "paragraph", paragraph: { rich_text: [rt("Ship "), rt("fast", { bold: true }), rt(" and "), rt("docs", {}, "https://x.dev")] } },
    { type: "bulleted_list_item", bulleted_list_item: { rich_text: [rt("one")] }, children: [{ type: "bulleted_list_item", bulleted_list_item: { rich_text: [rt("nested")] } }] },
    { type: "bulleted_list_item", bulleted_list_item: { rich_text: [rt("two")] } },
    { type: "numbered_list_item", numbered_list_item: { rich_text: [rt("first")] } },
    { type: "numbered_list_item", numbered_list_item: { rich_text: [rt("second")] } },
    { type: "to_do", to_do: { rich_text: [rt("done")], checked: true } },
    { type: "code", code: { rich_text: [rt("pnpm test")], language: "bash" } },
    { type: "divider", divider: {} },
    { type: "callout", callout: { rich_text: [rt("Heads up")], icon: { type: "emoji", emoji: "💡" } } },
    {
      type: "table",
      table: {},
      children: [
        { type: "table_row", table_row: { cells: [[rt("A")], [rt("B")]] } },
        { type: "table_row", table_row: { cells: [[rt("1")], [rt("2|3")]] } },
      ],
    },
    { type: "child_page", child_page: { title: "Sub page" } },
  ];
  const md = blocksToMarkdown(blocks);
  assert.equal(
    md,
    [
      "# Plan",
      "",
      "Ship **fast** and [docs](https://x.dev)",
      "",
      "- one",
      "  - nested",
      "- two",
      "1. first",
      "2. second",
      "- [x] done",
      "",
      "```bash\npnpm test\n```",
      "",
      "---",
      "",
      "> 💡 Heads up",
      "",
      "| A | B |\n| --- | --- |\n| 1 | 2\\|3 |",
      "",
      "📄 Sub page",
    ].join("\n"),
  );
});

test("markdown becomes notion blocks, long text split at 2000 chars", () => {
  const long = "x".repeat(RICH_MAX + 10);
  const blocks = markdownToBlocks(`# Title\n\nHello **bold** [link](https://a.b)\n\n- [ ] task\n- item\n\n1. first\n\n\`\`\`ts\nconst a = 1;\n\`\`\`\n\n---\n\n> quote\n\n${long}\n\n| a | b |\n| - | - |\n| 1 | 2 |`);
  const types = blocks.map((b) => b.type);
  assert.deepEqual(types, ["heading_1", "paragraph", "to_do", "bulleted_list_item", "numbered_list_item", "code", "divider", "quote", "paragraph", "table"]);
  const para = blocks[1].paragraph as { rich_text: Array<{ text: { content: string; link?: { url: string } }; annotations?: { bold?: boolean } }> };
  assert.deepEqual(
    para.rich_text.map((r) => [r.text.content, !!r.annotations?.bold, r.text.link?.url ?? null]),
    [["Hello ", false, null], ["bold", true, null], [" ", false, null], ["link", false, "https://a.b"]],
  );
  assert.equal((blocks[5].code as { language: string }).language, "typescript");
  const big = blocks[8].paragraph as { rich_text: Array<{ text: { content: string } }> };
  assert.equal(big.rich_text.length, 2);
  assert.equal(big.rich_text[0].text.content.length, RICH_MAX);
  const table = blocks[9].table as { table_width: number; children: unknown[] };
  assert.equal(table.table_width, 2);
  assert.equal(table.children.length, 2);
});

test("notion ids are normalized and checked", () => {
  assert.equal(checkNotionId("0123456789abcdef0123456789ABCDEF"), "01234567-89ab-cdef-0123-456789abcdef");
  assert.throws(() => checkNotionId("../secrets"), isApp(400, "bad_request"));
});

test("notion read: page metadata + paginated children as markdown", async () => {
  const repo = memoryRepo({});
  const t = createTokenManager({ repo, fetch, now: Date.now, encrypt: enc, decrypt: dec, providers });
  const pid = "01234567-89ab-cdef-0123-456789abcdef";
  const { f, calls } = mockFetch((url) => {
    if (url.endsWith(`/pages/${pid}`)) return json({ object: "page", id: pid, url: "https://notion.so/p", icon: { type: "emoji", emoji: "📘" }, properties: { Name: { type: "title", title: [rt("Roadmap")] } } });
    if (url.includes(`/blocks/${pid}/children`) && !url.includes("start_cursor")) {
      return json({ results: [{ id: "b1", type: "paragraph", paragraph: { rich_text: [rt("Hello")] } }], has_more: true, next_cursor: "c2" });
    }
    if (url.includes("start_cursor=c2")) return json({ results: [{ id: "b2", type: "heading_2", heading_2: { rich_text: [rt("Q4")] } }], has_more: false });
    return json({}, 404);
  });
  const n = createNotion(t, f);
  const page = await n.read("u1", pid);
  assert.equal(page.title, "Roadmap");
  assert.equal(page.icon, "📘");
  assert.equal(page.markdown, "Hello\n\n## Q4");
  assert.ok(calls.every((c) => new Headers(c.init.headers).get("Notion-Version") === "2022-06-28"));
});

test("notion createPage sends 100 blocks then appends the rest", async () => {
  const repo = memoryRepo({});
  const t = createTokenManager({ repo, fetch, now: Date.now, encrypt: enc, decrypt: dec, providers });
  const { f, calls } = mockFetch((url) => (url.endsWith("/pages") ? json({ object: "page", id: "new-page", url: "https://notion.so/new", properties: {} }) : json({ results: [] })));
  const n = createNotion(t, f);
  const md = Array.from({ length: 150 }, (_, i) => `Paragraph ${i}`).join("\n\n");
  await n.createPage("u1", { parentId: "0123456789abcdef0123456789abcdef", title: "Doc", markdown: md });
  const create = JSON.parse(String(calls[0].init.body));
  assert.equal(create.parent.page_id, "01234567-89ab-cdef-0123-456789abcdef");
  assert.equal(create.children.length, 100);
  assert.equal(calls[1].init.method, "PATCH");
  assert.equal(JSON.parse(String(calls[1].init.body)).children.length, 50);
});

// ---- Drive --------------------------------------------------------------------------

test("drive read kinds and export targets", () => {
  assert.equal(readKind(GDOC), "markdown");
  assert.equal(readKind(GSHEET), "csv");
  assert.equal(readKind("application/pdf"), "pdf");
  assert.equal(readKind("image/png"), "none");
  assert.equal(exportMime(GDOC), "text/markdown");
  assert.equal(exportMime(GSHEET), "text/csv");
  assert.equal(exportMime("application/pdf"), null);
});

test("drive read: a Google Doc is exported as markdown; unreadable files are described", async () => {
  const repo = memoryRepo({});
  repo.rows.set("u1:google_drive", { accessTokenEnc: "enc:at", refreshTokenEnc: null, expiresAt: null, needsReauth: false, accountLogin: "x" });
  const t = createTokenManager({ repo, fetch, now: Date.now, encrypt: enc, decrypt: dec, providers });
  const { f, calls } = mockFetch((url) => {
    if (url.includes("/files/doc1234567890?")) return json({ id: "doc1234567890", name: "Plan", mimeType: GDOC, webViewLink: "https://docs.google.com/d" });
    if (url.includes("/files/doc1234567890/export")) return new Response("# Plan\n\nShip it.");
    if (url.includes("/files/img1234567890?")) return json({ id: "img1234567890", name: "cat.png", mimeType: "image/png", size: "2048" });
    return json({}, 404);
  });
  const d = createDrive(t, f);
  const doc = await d.read("u1", "doc1234567890");
  assert.equal(doc.format, "markdown");
  assert.equal(doc.text, "# Plan\n\nShip it.");
  assert.ok(calls.some((c) => c.url.includes("mimeType=text%2Fmarkdown")));
  const img = await d.read("u1", "img1234567890");
  assert.equal(img.format, "metadata");
  assert.match(img.text, /cat\.png/);
  await assert.rejects(d.read("u1", "nope1234567890"), isApp(404, "not_found"));
  await assert.rejects(d.read("u1", "../../etc"), isApp(400, "bad_request"));
});

test("drive list asks only for non-trashed files and escapes the query", async () => {
  const repo = memoryRepo({});
  repo.rows.set("u1:google_drive", { accessTokenEnc: "enc:at", refreshTokenEnc: null, expiresAt: null, needsReauth: false, accountLogin: "x" });
  const t = createTokenManager({ repo, fetch, now: Date.now, encrypt: enc, decrypt: dec, providers });
  const { f, calls } = mockFetch(() => json({ files: [{ id: "f1", name: "A", mimeType: "application/pdf" }] }));
  const d = createDrive(t, f);
  const r = await d.list("u1", { q: "nick's plan" });
  assert.equal(r.files[0].kind, "pdf");
  const q = new URL(calls[0].url).searchParams.get("q")!;
  assert.match(q, /trashed = false/);
  assert.ok(q.includes("nick\\'s plan"));
  assert.equal(new URL(calls[0].url).searchParams.get("orderBy"), null);
});

test("drive upload: multipart with Google Doc conversion", async () => {
  const repo = memoryRepo({});
  repo.rows.set("u1:google_drive", { accessTokenEnc: "enc:at", refreshTokenEnc: null, expiresAt: null, needsReauth: false, accountLogin: "x" });
  const t = createTokenManager({ repo, fetch, now: Date.now, encrypt: enc, decrypt: dec, providers });
  const { f, calls } = mockFetch(() => json({ id: "new1", name: "Doc", mimeType: GDOC }));
  const d = createDrive(t, f);
  const file = await d.upload("u1", { name: "Doc", mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", data: Buffer.from("PK"), convert: true });
  assert.equal(file.id, "new1");
  assert.match(calls[0].url, /uploadType=multipart/);
  const body = String(Buffer.from(calls[0].init.body as Buffer));
  assert.ok(body.includes(`"mimeType":"${GDOC}"`));
});

// ---- chat tools ------------------------------------------------------------------------

test("apps intent: Drive and Notion mentions with search words", () => {
  assert.deepEqual(appsIntent("summarize the roadmap page in my Notion"), { drive: false, notion: true, query: "roadmap" });
  assert.equal(appsIntent("what's in my Google Drive about the Q4 budget?")?.drive, true);
  assert.equal(appsIntent('find "Launch plan" in drive')?.query, "Launch plan");
  assert.equal(appsIntent("how do I drive a car"), null);
  assert.equal(appsIntent("tell me a joke"), null);
});

function fakeTools(log: string[]): AppTools {
  return {
    async drive_search(_u, q) {
      log.push(`drive_search:${q}`);
      return [{ id: "f1", title: "Budget", url: "https://docs.google.com/b", note: "sheet" }];
    },
    async drive_read(_u, id) {
      log.push(`drive_read:${id}`);
      return { title: "Budget", url: "https://docs.google.com/b", text: "Q4,100" };
    },
    async notion_search(_u, q) {
      log.push(`notion_search:${q}`);
      return [];
    },
    async notion_read(_u, id) {
      log.push(`notion_read:${id}`);
      return { title: "Roadmap", url: "https://notion.so/r", text: "# Roadmap" };
    },
  };
}

test("apps grounding: searches and reads the connected app, cites as numbered documents", async () => {
  const calls: string[] = [];
  const g = await appsGround("u1", "what does my Google Drive say about the budget", [], { prefix: "D", firstId: 3 }, {
    tools: fakeTools(calls),
    connected: async () => new Set(["google_drive"]),
    configured: () => true,
  });
  assert.deepEqual(calls, ["drive_search:budget", "drive_read:f1"]);
  assert.deepEqual(g!.items.map((i) => i.id), ["D3", "D4"]);
  assert.match(g!.items[1].title, /Budget \(Google Drive\)/);
  assert.match(g!.hint!, /\[D3\], \[D4\]/);
  assert.match(g!.hint!, /never say you changed/);
});

test("apps grounding: not connected says so, attached refs are read", async () => {
  const calls: string[] = [];
  const deps = { tools: fakeTools(calls), connected: async () => new Set<ProviderId>(["notion"]), configured: () => true };
  const off = await appsGround("u1", "what's in my google drive", [], {}, { ...deps, connected: async () => new Set<ProviderId>() });
  assert.equal(off!.items.length, 0);
  assert.match(off!.hint!, /connect Google Drive in Apps/);
  const attached = await appsGround("u1", "summarize this", [{ provider: "notion", id: "01234567-89ab-cdef-0123-456789abcdef" }], {}, deps);
  assert.deepEqual(calls, ["notion_read:01234567-89ab-cdef-0123-456789abcdef"]);
  assert.equal(attached!.items[0].text, "# Roadmap");
  assert.equal(await appsGround(null, "my notion", [], {}, deps), null);
  // Notion search empty: explains sharing instead of guessing.
  const none = await appsGround("u1", "find the offsite page in notion", [], {}, deps);
  assert.match(none!.hint!, /share/i);
});

// ---- picker ---------------------------------------------------------------------------

test("picker app id is the project number from the client id", () => {
  assert.equal(projectNumber(CLIENT), "123456789012");
  assert.equal(projectNumber("abc.apps.googleusercontent.com"), null);
});

test("picker: start, page without API key, done verifies picked files once", async () => {
  const store = memoryFlows();
  const repo = memoryRepo({});
  repo.rows.set("u1:google_drive", { accessTokenEnc: "enc:at", refreshTokenEnc: null, expiresAt: null, needsReauth: false, accountLogin: "x" });
  const tokens = createTokenManager({ repo, fetch, now: Date.now, encrypt: enc, decrypt: dec, providers });
  let key: string | undefined;
  const p = createPicker({
    store,
    tokens,
    now: Date.now,
    apiKey: () => key,
    clientId: () => CLIENT,
    baseUrl: () => "https://sparky.example",
    verify: async (_u, id) => id !== "gone123456789",
  });
  const s = await p.start("u1");
  const ticket = new URL(s.url).searchParams.get("ticket")!;
  assert.equal(new URL(s.url).pathname, "/connect/google_drive/picker");
  const noKey = await p.view(ticket);
  assert.equal(noKey.ok, false);
  assert.match(pickerPage(noKey, "n"), /GOOGLE_PICKER_API_KEY/);
  key = "AIza-test";
  const v = await p.view(ticket);
  assert.equal(v.ok, true);
  const html = pickerPage(v, "n0nce");
  assert.match(html, /"appId":"123456789012"/);
  assert.ok(!html.includes("</script><script>alert"));
  const done = await p.done(ticket, ["file123456789", "gone123456789", "file123456789", "bad id"]);
  assert.equal(done.picked, 1);
  const link = new URL(done.link);
  assert.equal(link.searchParams.get("state"), s.state);
  assert.equal(link.searchParams.get("mode"), "picker");
  await assert.rejects(p.done(ticket, []), isApp(400, "invalid_ticket"));
  assert.equal((await p.view(ticket)).ok, false);
  assert.equal((await p.view("")).ok, false);
});
