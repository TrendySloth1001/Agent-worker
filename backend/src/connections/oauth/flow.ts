import { randomBytes } from "node:crypto";
import { config } from "../../config.js";
import { db } from "../../db/prisma.js";
import { AppError } from "../../util/errors.js";
import { log } from "../../util/logger.js";
import { pkceChallenge, sha256 } from "../../auth/githubWeb.js";
import { PROVIDERS, callToken, parseGrant, providerConfigured, type AccountProfile, type OAuthProvider, type ProviderId, type TokenGrant } from "./providers.js";
import { connectorTokens, providerNotConfigured } from "./tokens.js";
import { isUserSafe } from "../../util/userMessages.js";

/**
 * The OAuth web flow of the connectors (authorization code, + PKCE where the
 * provider supports it), the same shape as GitHub's (src/auth/githubWeb.ts):
 *
 *  1. start(): a flow row (hashed state, verifier, provider, user) and the
 *     provider's authorize URL, opened by the app.
 *  2. GET /connect/:provider/callback?code&state: the state must match a
 *     pending, unexpired flow of that provider (claimed once); the code is
 *     exchanged, the account read, the tokens stored encrypted; a one-time
 *     ticket (hashed, 2 min) goes back via sparky://auth/connect?provider&ticket&state.
 *  3. redeem(): the app swaps the ticket, once, for the connection summary.
 */

export const CONNECT_DEEP_LINK = "sparky://auth/connect";
export const callbackPath = (p: ProviderId) => `/connect/${p}/callback`;
export const FLOW_TTL_MS = 10 * 60_000;
export const TICKET_TTL_MS = 2 * 60_000;
const PURGE_AFTER_MS = 24 * 60 * 60_000;
const TIMEOUT_MS = 12_000;

export type FlowMode = "connect" | "picker";
export type FlowStatus = "pending" | "exchanging" | "ready" | "redeemed" | "failed";
export type FlowResult = { login: string; picked?: number };

export type FlowRow = {
  id: string;
  provider: ProviderId;
  mode: FlowMode;
  stateHash: string;
  codeVerifier: string;
  userId: string;
  status: FlowStatus;
  expiresAt: Date;
  ticketHash: string | null;
  ticketExpiresAt: Date | null;
  result: FlowResult | null;
};

export type NewFlow = Pick<FlowRow, "provider" | "mode" | "stateHash" | "codeVerifier" | "userId" | "expiresAt">;

export interface FlowStore {
  create(row: NewFlow): Promise<void>;
  /** pending + unexpired + same provider/mode → exchanging. */
  claim(provider: ProviderId, mode: FlowMode, stateHash: string, now: Date): Promise<FlowRow | null>;
  /** The pending, unexpired row (picker pages read it before finishing). */
  peek(provider: ProviderId, mode: FlowMode, stateHash: string, now: Date): Promise<FlowRow | null>;
  ready(id: string, ticketHash: string, ticketExpiresAt: Date, result: FlowResult): Promise<void>;
  fail(id: string): Promise<void>;
  /** ready + unexpired ticket + same user → redeemed. The row when this call won. */
  consume(provider: ProviderId, ticketHash: string, now: Date, userId: string): Promise<FlowRow | null>;
  hasConnection(userId: string, provider: ProviderId): Promise<boolean>;
  purge(before: Date): Promise<void>;
}

export type FlowDeps = {
  fetch: typeof fetch;
  now: () => number;
  store: FlowStore;
  redirectUri: (p: ProviderId) => string;
  save: (userId: string, provider: ProviderId, grant: TokenGrant, profile: AccountProfile) => Promise<void>;
  providers?: Record<ProviderId, OAuthProvider>;
};

/** Where the callback sends the browser: always a sparky:// deep link. */
export type ConnectCallback = { ok: boolean; link: string; provider: ProviderId; providerName: string; message: string };

const b64url = (b: Buffer) => b.toString("base64url");

export function connectDeepLink(params: Record<string, string | null | undefined>): string {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v) q.set(k, v);
  return `${CONNECT_DEEP_LINK}?${q.toString()}`;
}

const messages = (name: string): Record<string, string> => ({
  access_denied: `Access was denied on ${name}.`,
  expired: `This ${name} connection expired or was already used. Start again from sparky.`,
  exchange_failed: `${name} did not accept the connection. Start again from sparky.`,
  bad_request: `${name} sent an incomplete answer. Start again from sparky.`,
  failed: `Could not finish connecting ${name}.`,
});

export function createOAuthFlow(deps: FlowDeps) {
  const providers = deps.providers ?? PROVIDERS;

  async function start(provider: ProviderId, userId: string): Promise<{ authorizeUrl: string; state: string; expiresIn: number }> {
    const p = providers[provider];
    if (!providerConfigured(p)) throw providerNotConfigured(p);
    const now = deps.now();
    await deps.store.purge(new Date(now - PURGE_AFTER_MS)).catch(() => undefined);
    const state = b64url(randomBytes(32));
    const verifier = p.pkce ? b64url(randomBytes(48)) : "";
    const first = !(await deps.store.hasConnection(userId, provider).catch(() => false));
    await deps.store.create({ provider, mode: "connect", stateHash: sha256(state), codeVerifier: verifier, userId, expiresAt: new Date(now + FLOW_TTL_MS) });
    const q = new URLSearchParams({
      client_id: p.clientId()!,
      redirect_uri: deps.redirectUri(provider),
      response_type: "code",
      state,
      ...(p.scopes.length ? { scope: p.scopes.join(" ") } : {}),
      ...(p.pkce ? { code_challenge: pkceChallenge(verifier), code_challenge_method: "S256" } : {}),
      ...p.authorizeParams(first),
    });
    return { authorizeUrl: `${p.authorizeUrl}?${q.toString()}`, state, expiresIn: FLOW_TTL_MS / 1000 };
  }

  async function exchange(p: OAuthProvider, code: string, verifier: string): Promise<TokenGrant> {
    const params: Record<string, string> = { grant_type: "authorization_code", code, redirect_uri: deps.redirectUri(p.id) };
    if (p.pkce && verifier) params.code_verifier = verifier;
    const res = await callToken(p, params, { fetch: deps.fetch }, TIMEOUT_MS);
    const grant = res.status < 300 ? parseGrant(res.json) : null;
    if (!grant) {
      log.warn("connector code exchange failed", { provider: p.id, error: String(res.json.error ?? res.status).slice(0, 60) });
      throw new AppError(502, "exchange_failed", messages(p.name).exchange_failed);
    }
    return grant;
  }

  /** GET /connect/:provider/callback. Never throws: every outcome is a deep link. */
  async function callback(provider: ProviderId, q: { code?: string; state?: string; error?: string }): Promise<ConnectCallback> {
    const p = providers[provider];
    const state = q.state ?? "";
    const msg = messages(p.name);
    const fail = (code: string, message?: string): ConnectCallback => {
      const m = isUserSafe(message) ? message : (msg[code] ?? msg.failed);
      return { ok: false, provider, providerName: p.name, message: m, link: connectDeepLink({ provider, error: code, message: m, state }) };
    };
    if (!state) return fail("bad_request");
    const flow = await deps.store.claim(provider, "connect", sha256(state), new Date(deps.now())).catch(() => null);
    if (!flow) return fail("expired");
    if (q.error || !q.code) {
      await deps.store.fail(flow.id).catch(() => undefined);
      return fail(q.error === "access_denied" ? "access_denied" : q.error ? "failed" : "bad_request");
    }
    try {
      const grant = await exchange(p, q.code, flow.codeVerifier);
      const profile = await p.profile(grant, { fetch: deps.fetch });
      await deps.save(flow.userId, provider, grant, profile);
      const ticket = b64url(randomBytes(32));
      await deps.store.ready(flow.id, sha256(ticket), new Date(deps.now() + TICKET_TTL_MS), { login: profile.login });
      return { ok: true, provider, providerName: p.name, message: "", link: connectDeepLink({ provider, ticket, state }) };
    } catch (e) {
      await deps.store.fail(flow.id).catch(() => undefined);
      if (e instanceof AppError) return fail(e.code, e.message);
      log.warn("connector flow failed", { provider, message: (e as Error).message.slice(0, 120) });
      return fail("failed");
    }
  }

  /** Swaps [ticket] once; only for the user who started the flow. */
  async function redeem(provider: ProviderId, ticket: string, userId: string): Promise<FlowRow> {
    const row = await deps.store.consume(provider, sha256(ticket), new Date(deps.now()), userId);
    if (!row) throw new AppError(400, "invalid_ticket", "This connection expired or was already used. Start again.");
    return row;
  }

  return { start, callback, redeem };
}

export type OAuthFlow = ReturnType<typeof createOAuthFlow>;

// ---- database store ---------------------------------------------------------

type DbRow = Omit<FlowRow, "provider" | "mode" | "status" | "result"> & { provider: string; mode: string; status: string; result: unknown };
const toRow = (r: DbRow): FlowRow => ({
  ...r,
  provider: r.provider as ProviderId,
  mode: r.mode as FlowMode,
  status: r.status as FlowStatus,
  result: (r.result ?? null) as FlowResult | null,
});
const FLOW_SELECT = {
  id: true, provider: true, mode: true, stateHash: true, codeVerifier: true, userId: true, status: true,
  expiresAt: true, ticketHash: true, ticketExpiresAt: true, result: true,
} as const;

export const prismaFlowStore: FlowStore = {
  async create(row) {
    await db().oAuthFlow.create({ data: row });
  },
  async claim(provider, mode, stateHash, now) {
    const n = await db().oAuthFlow.updateMany({
      where: { stateHash, provider, mode, status: "pending", expiresAt: { gt: now } },
      data: { status: "exchanging" },
    });
    if (n.count !== 1) return null;
    const r = await db().oAuthFlow.findUnique({ where: { stateHash }, select: FLOW_SELECT });
    return r ? toRow(r) : null;
  },
  async peek(provider, mode, stateHash, now) {
    const r = await db().oAuthFlow.findFirst({ where: { stateHash, provider, mode, status: "pending", expiresAt: { gt: now } }, select: FLOW_SELECT });
    return r ? toRow(r) : null;
  },
  async ready(id, ticketHash, ticketExpiresAt, result) {
    await db().oAuthFlow.update({ where: { id }, data: { status: "ready", ticketHash, ticketExpiresAt, result, codeVerifier: "" } });
  },
  async fail(id) {
    await db().oAuthFlow.update({ where: { id }, data: { status: "failed", codeVerifier: "" } });
  },
  async consume(provider, ticketHash, now, userId) {
    const n = await db().oAuthFlow.updateMany({
      where: { ticketHash, provider, userId, status: "ready", ticketExpiresAt: { gt: now } },
      data: { status: "redeemed" },
    });
    if (n.count !== 1) return null;
    const r = await db().oAuthFlow.findUnique({ where: { ticketHash }, select: FLOW_SELECT });
    return r ? toRow(r) : null;
  },
  async hasConnection(userId, provider) {
    return (await db().connection.count({ where: { userId, provider } })) > 0;
  },
  async purge(before) {
    await db().oAuthFlow.deleteMany({ where: { createdAt: { lt: before } } });
  },
};

export const connectRedirectUri = (p: ProviderId) => `${config.publicBaseUrl}${callbackPath(p)}`;

export const oauthFlow = createOAuthFlow({
  fetch: (...a) => fetch(...a),
  now: () => Date.now(),
  store: prismaFlowStore,
  redirectUri: connectRedirectUri,
  save: (u, p, g, prof) => connectorTokens.save(u, p, g, prof),
});
