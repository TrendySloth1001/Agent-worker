import { createHash, randomBytes } from "node:crypto";
import { config } from "../config.js";
import { encryptSecret } from "../connections/crypto.js";
import { ACCESS_TOKEN_URL, GITHUB_SCOPES, connectionRow, notConfigured, type ConnectionRow, type DeviceGrant, type GithubAccount } from "../connections/deviceFlow.js";
import { listConnections, saveGithubConnection, type ConnectionSummary } from "../connections/store.js";
import { db, tx } from "../db/prisma.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { GITHUB_SSO_SCOPES, githubGrantProfile, saveGrantConnection } from "./githubSso.js";
import type { Tokens, UserRow } from "./service.js";
import { linkIdentity, resolveSsoUser, ssoSessionFor, type IdentitySummary, type SsoOutcome, type SsoProfile } from "./sso.js";
import { isUserSafe } from "../util/userMessages.js";

/**
 * GitHub over the OAuth web flow (authorization code + PKCE), one tap instead
 * of typing a device code:
 *
 *  1. start(): a flow row (hashed state, PKCE verifier, mode, user) and the
 *     github.com/login/oauth/authorize URL the app opens.
 *  2. GitHub sends the browser to GET /auth/github/callback?code&state. The
 *     state must match a pending, unexpired flow (claimed once); the code is
 *     exchanged with the client secret AND the verifier; the account is
 *     resolved / linked / connected exactly like the device flow does; a
 *     random one-time ticket (stored hashed, 2 min) goes back to the app via
 *     the deep link sparky://auth/github?ticket&mode&state.
 *  3. redeem(): the app swaps the ticket, once, for the session (sign-in) or
 *     the connection summary (connect/link).
 *
 * Flows live in the database (table github_oauth_flows), so a restart between
 * start and callback costs nothing. GitHub's token never leaves the server.
 */

export type WebMode = "signin" | "connect" | "link";
export const WEB_MODES: readonly WebMode[] = ["signin", "connect", "link"];
export type WebStatus = "pending" | "exchanging" | "ready" | "redeemed" | "failed";

export const AUTHORIZE_URL = "https://github.com/login/oauth/authorize";
export const DEEP_LINK = "sparky://auth/github";
export const CALLBACK_PATH = "/auth/github/callback";
/** Where a web app origin receives the ticket. */
export const WEB_RETURN_PATH = "/api/auth/github/return";
/** How long the user has to approve on GitHub. */
export const FLOW_TTL_MS = 10 * 60_000;
/** How long the app has to redeem the ticket after the callback. */
export const TICKET_TTL_MS = 2 * 60_000;
/** Finished/abandoned rows are deleted after this. */
const PURGE_AFTER_MS = 24 * 60 * 60_000;
const TIMEOUT_MS = 12_000;

/** What the callback resolved; never any token. */
export type WebResult =
  | { mode: "signin"; userId: string; outcome: SsoOutcome; login: string }
  | { mode: "connect"; account: GithubAccount }
  | { mode: "link"; identity: IdentitySummary; account: GithubAccount };

export type WebFlowRow = {
  id: string;
  stateHash: string;
  codeVerifier: string;
  mode: WebMode;
  userId: string | null;
  device: string | null;
  status: WebStatus;
  expiresAt: Date;
  ticketHash: string | null;
  ticketExpiresAt: Date | null;
  result: WebResult | null;
};

export type NewWebFlow = Pick<WebFlowRow, "stateHash" | "codeVerifier" | "mode" | "userId" | "device" | "expiresAt">;

/** Persistence; every state change is a single conditional write (no double use). */
export interface WebFlowStore {
  create(row: NewWebFlow): Promise<void>;
  /** pending + unexpired → exchanging. The row, or null when there is none to claim. */
  claim(stateHash: string, now: Date): Promise<WebFlowRow | null>;
  ready(id: string, ticketHash: string, ticketExpiresAt: Date, result: WebResult): Promise<void>;
  fail(id: string): Promise<void>;
  byTicket(ticketHash: string): Promise<WebFlowRow | null>;
  /** ready + unexpired ticket (+ same user for connect/link) → redeemed. True when this call won. */
  consume(ticketHash: string, now: Date, userId: string | null): Promise<boolean>;
  purge(before: Date): Promise<void>;
}

export type GithubWebDeps = {
  clientId: () => string | undefined;
  clientSecret: () => string | undefined;
  /** Absolute callback URL registered on the OAuth app. */
  redirectUri: () => string;
  fetch: typeof fetch;
  now: () => number;
  store: WebFlowStore;
  /** Finds or creates the account (no session yet). */
  resolve: (p: SsoProfile) => Promise<{ user: { id: string }; outcome: SsoOutcome }>;
  link: (userId: string, p: SsoProfile) => Promise<IdentitySummary>;
  encrypt: (plain: string) => string;
  saveConnection: (row: ConnectionRow) => Promise<void>;
  /** The session handed out when a sign-in ticket is redeemed. */
  session: (userId: string, device: string | null) => Promise<{ user: UserRow; tokens: Tokens }>;
  connection: (userId: string) => Promise<ConnectionSummary | null>;
  /** Origins of the web app that may receive the ticket instead of the deep link. */
  webOrigins?: () => readonly string[];
};

export type WebStart = { authorizeUrl: string; state: string; mode: WebMode; expiresIn: number };

export type WebRedeem =
  | { mode: "signin"; user: UserRow; tokens: Tokens; outcome: SsoOutcome; login: string }
  | { mode: "connect"; connection: ConnectionSummary | null }
  | { mode: "link"; identity: IdentitySummary; connection: ConnectionSummary | null };

/** Where the callback sends the browser: a sparky:// deep link, or the web app for an allow-listed web sign-in. */
export type WebCallback = { ok: boolean; link: string; mode: WebMode | null; message: string };

const b64url = (b: Buffer) => b.toString("base64url");
export const sha256 = (s: string) => createHash("sha256").update(s).digest("hex");
/** RFC 7636 S256: BASE64URL(SHA256(verifier)). */
export const pkceChallenge = (verifier: string) => b64url(createHash("sha256").update(verifier).digest());

export const webNotConfigured = () =>
  new AppError(503, "github_oauth_not_configured", "GitHub sign-in isn't available right now.");

const deepLink = (params: Record<string, string | null | undefined>) => {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v) q.set(k, v);
  return `${DEEP_LINK}?${q.toString()}`;
};

const webLink = (origin: string, params: Record<string, string | null | undefined>) => {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v) q.set(k, v);
  return `${origin}${WEB_RETURN_PATH}?${q.toString()}`;
};

const MESSAGES: Record<string, string> = {
  access_denied: "Access was denied on GitHub.",
  expired: "This GitHub sign-in expired or was already used. Start again from sparky.",
  exchange_failed: "GitHub did not accept the sign-in. Start again from sparky.",
  bad_request: "GitHub sent an incomplete answer. Start again from sparky.",
  failed: "Could not finish with GitHub.",
};

export function createGithubWeb(deps: GithubWebDeps) {
  const configured = () => !!deps.clientId() && !!deps.clientSecret();

  const allowedOrigins = () => deps.webOrigins?.() ?? [];

  /** The web origin carried in a state (`<b64url origin>.<random>`), only when it is allow-listed. */
  function originOfState(state: string): string | null {
    const [head, rest] = state.split(".");
    if (!head || !rest) return null;
    const origin = Buffer.from(head, "base64url").toString("utf8");
    return allowedOrigins().includes(origin) ? origin : null;
  }

  async function start(input: { mode: WebMode; userId: string | null; device: string | null; returnOrigin?: string | null }): Promise<WebStart> {
    const clientId = deps.clientId();
    if (!clientId) throw notConfigured();
    if (!deps.clientSecret()) throw webNotConfigured();
    if (input.mode === "signin" ? input.userId !== null : !input.userId) {
      throw new AppError(403, "forbidden", "Sign in with an account to connect services");
    }
    const now = deps.now();
    await deps.store.purge(new Date(now - PURGE_AFTER_MS)).catch(() => undefined);
    if (input.returnOrigin && (input.mode !== "signin" || !allowedOrigins().includes(input.returnOrigin))) {
      throw new AppError(400, "bad_request", "Something about that request wasn't right — please try again.");
    }
    const random = b64url(randomBytes(32));
    const state = input.returnOrigin ? `${b64url(Buffer.from(input.returnOrigin))}.${random}` : random;
    const verifier = b64url(randomBytes(48));
    await deps.store.create({
      stateHash: sha256(state),
      codeVerifier: verifier,
      mode: input.mode,
      userId: input.mode === "signin" ? null : input.userId,
      device: input.device?.slice(0, 120) ?? null,
      expiresAt: new Date(now + FLOW_TTL_MS),
    });
    const q = new URLSearchParams({
      client_id: clientId,
      redirect_uri: deps.redirectUri(),
      // Sign-in and linking only ask who you are; connecting asks for repos.
      scope: input.mode === "connect" ? GITHUB_SCOPES : GITHUB_SSO_SCOPES,
      state,
      code_challenge: pkceChallenge(verifier),
      code_challenge_method: "S256",
      allow_signup: "true",
    });
    return { authorizeUrl: `${AUTHORIZE_URL}?${q.toString()}`, state, mode: input.mode, expiresIn: FLOW_TTL_MS / 1000 };
  }

  /** Code → token (client secret + PKCE verifier). */
  async function exchange(code: string, verifier: string): Promise<DeviceGrant> {
    const res = await deps.fetch(ACCESS_TOKEN_URL, {
      method: "POST",
      headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded", "User-Agent": "AgentWorker" },
      body: new URLSearchParams({
        client_id: deps.clientId() ?? "",
        client_secret: deps.clientSecret() ?? "",
        code,
        redirect_uri: deps.redirectUri(),
        code_verifier: verifier,
      }).toString(),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    const j = (await res.json().catch(() => ({}))) as Record<string, unknown>;
    if (!res.ok || typeof j.access_token !== "string") {
      log.warn("github web flow: code exchange failed", { error: String(j.error ?? res.status).slice(0, 60) });
      throw new AppError(502, "exchange_failed", MESSAGES.exchange_failed);
    }
    return {
      accessToken: j.access_token,
      refreshToken: typeof j.refresh_token === "string" ? j.refresh_token : null,
      expiresIn: Number(j.expires_in) > 0 ? Number(j.expires_in) : 0,
      scope: typeof j.scope === "string" ? j.scope : "",
    };
  }

  /** What the grant becomes for [flow]'s mode (same rules as the device flow). */
  async function apply(flow: WebFlowRow, grant: DeviceGrant): Promise<WebResult> {
    const { u, profile } = await githubGrantProfile(deps.fetch, grant);
    const account: GithubAccount = { login: u.login, id: u.id, avatarUrl: u.avatarUrl, scopes: u.scopes };
    switch (flow.mode) {
      case "signin": {
        const { user, outcome } = await deps.resolve(profile);
        await saveGrantConnection(deps, u, user.id, grant);
        return { mode: "signin", userId: user.id, outcome, login: u.login };
      }
      case "link": {
        const identity = await deps.link(flow.userId!, profile);
        await saveGrantConnection(deps, u, flow.userId!, grant);
        return { mode: "link", identity, account };
      }
      case "connect":
        // Connecting is the point here: a failure to save is the flow's failure.
        await deps.saveConnection(connectionRow(u, flow.userId!, grant, deps));
        return { mode: "connect", account };
    }
  }

  /** GET /auth/github/callback. Never throws: every outcome is a deep link. */
  async function callback(q: { code?: string; state?: string; error?: string }): Promise<WebCallback> {
    const state = q.state ?? "";
    const origin = originOfState(state);
    const target = (params: Record<string, string | null | undefined>) => (origin ? webLink(origin, params) : deepLink(params));
    const fail = (code: string, mode: WebMode | null, message?: string): WebCallback => {
      const msg = isUserSafe(message) ? message : (MESSAGES[code] ?? MESSAGES.failed);
      return { ok: false, mode, message: msg, link: target({ error: code, message: msg, mode, state }) };
    };
    if (!state) return fail("bad_request", null);
    const flow = await deps.store.claim(sha256(state), new Date(deps.now())).catch(() => null);
    // Unknown, expired or already used state: nothing is exchanged.
    if (!flow) return fail("expired", null);
    if (q.error || !q.code) {
      await deps.store.fail(flow.id).catch(() => undefined);
      return fail(q.error === "access_denied" ? "access_denied" : q.error ? "failed" : "bad_request", flow.mode);
    }
    try {
      const grant = await exchange(q.code, flow.codeVerifier);
      const result = await apply(flow, grant);
      const ticket = b64url(randomBytes(32));
      await deps.store.ready(flow.id, sha256(ticket), new Date(deps.now() + TICKET_TTL_MS), result);
      return { ok: true, mode: flow.mode, message: "", link: target({ ticket, mode: flow.mode, state }) };
    } catch (e) {
      await deps.store.fail(flow.id).catch(() => undefined);
      if (e instanceof AppError) return fail(e.code, flow.mode, e.message);
      log.warn("github web flow failed", { mode: flow.mode, message: (e as Error).message.slice(0, 120) });
      return fail("failed", flow.mode);
    }
  }

  const invalidTicket = () => new AppError(400, "invalid_ticket", "This GitHub sign-in expired or was already used. Start again.");

  /** The mode of [ticket] without using it (routes pick the public or signed-in handler). */
  async function ticketMode(ticket: string): Promise<WebMode | null> {
    const row = await deps.store.byTicket(sha256(ticket));
    return row?.mode ?? null;
  }

  /**
   * Swaps [ticket] for its result, once. [caller] is the signed-in user for
   * connect/link (must be the one who started the flow), null for sign-in.
   */
  async function redeem(ticket: string, caller: string | null): Promise<WebRedeem> {
    const hash = sha256(ticket);
    const row = await deps.store.byTicket(hash);
    if (!row || !row.result) throw invalidTicket();
    // Connect/link tickets only work for the account that started the flow.
    const owner = row.mode === "signin" ? null : caller;
    if (row.mode !== "signin" && (!caller || row.userId !== caller)) throw invalidTicket();
    if (!(await deps.store.consume(hash, new Date(deps.now()), owner))) throw invalidTicket();
    const r = row.result;
    switch (r.mode) {
      case "signin": {
        const s = await deps.session(r.userId, row.device);
        return { mode: "signin", ...s, outcome: r.outcome, login: r.login };
      }
      case "connect":
        return { mode: "connect", connection: await deps.connection(row.userId!) };
      case "link":
        return { mode: "link", identity: r.identity, connection: await deps.connection(row.userId!) };
    }
  }

  return { configured, start, callback, redeem, ticketMode };
}

export type GithubWeb = ReturnType<typeof createGithubWeb>;

// ---- database store --------------------------------------------------------

type DbRow = {
  id: string;
  stateHash: string;
  codeVerifier: string;
  mode: string;
  userId: string | null;
  device: string | null;
  status: string;
  expiresAt: Date;
  ticketHash: string | null;
  ticketExpiresAt: Date | null;
  result: unknown;
};

const toRow = (r: DbRow): WebFlowRow => ({ ...r, mode: r.mode as WebMode, status: r.status as WebStatus, result: (r.result ?? null) as WebResult | null });

export const prismaWebStore: WebFlowStore = {
  async create(row) {
    await db().githubOAuthFlow.create({ data: row });
  },
  async claim(stateHash, now) {
    const n = await db().githubOAuthFlow.updateMany({
      where: { stateHash, status: "pending", expiresAt: { gt: now } },
      data: { status: "exchanging" },
    });
    if (n.count !== 1) return null;
    const r = await db().githubOAuthFlow.findUnique({ where: { stateHash } });
    return r ? toRow(r) : null;
  },
  async ready(id, ticketHash, ticketExpiresAt, result) {
    await db().githubOAuthFlow.update({
      where: { id },
      data: { status: "ready", ticketHash, ticketExpiresAt, result: result as object, codeVerifier: "" },
    });
  },
  async fail(id) {
    await db().githubOAuthFlow.update({ where: { id }, data: { status: "failed", codeVerifier: "" } });
  },
  async byTicket(ticketHash) {
    const r = await db().githubOAuthFlow.findUnique({ where: { ticketHash } });
    return r ? toRow(r) : null;
  },
  async consume(ticketHash, now, userId) {
    const n = await db().githubOAuthFlow.updateMany({
      where: { ticketHash, status: "ready", ticketExpiresAt: { gt: now }, ...(userId ? { userId } : { mode: "signin" }) },
      data: { status: "redeemed" },
    });
    return n.count === 1;
  },
  async purge(before) {
    await db().githubOAuthFlow.deleteMany({ where: { createdAt: { lt: before } } });
  },
};

export const githubWeb = createGithubWeb({
  clientId: () => config.githubOAuth.clientId,
  clientSecret: () => config.githubOAuth.clientSecret,
  redirectUri: () => `${config.publicBaseUrl}${CALLBACK_PATH}`,
  fetch: (...a) => fetch(...a),
  now: () => Date.now(),
  store: prismaWebStore,
  resolve: (p) => tx((c) => resolveSsoUser(c, p)),
  link: linkIdentity,
  encrypt: (plain) => encryptSecret(plain),
  saveConnection: saveGithubConnection,
  session: ssoSessionFor,
  connection: async (userId) => (await listConnections(userId)).find((c) => c.provider === "github") ?? null,
  webOrigins: () => config.webAppOrigins,
});
