import { db } from "../../db/prisma.js";
import { AppError } from "../../util/errors.js";
import { log } from "../../util/logger.js";
import { decryptSecret, encryptSecret } from "../crypto.js";
import { PROVIDERS, callToken, parseGrant, type AccountProfile, type OAuthProvider, type ProviderId, type TokenGrant } from "./providers.js";

/**
 * Tokens of the OAuth connectors, encrypted at rest in `connections`:
 * saving a grant, handing out a fresh access token (refreshed shortly before
 * it expires, one refresh per user+provider at a time; a rotated refresh
 * token is written with a compare-and-swap so two refreshes never lose it),
 * flagging a dead grant for Reconnect, and disconnecting (revoke at the
 * provider, then delete). Tokens never leave this module except as the
 * Authorization header of a provider call.
 */

export type StoredConnection = {
  accessTokenEnc: string;
  refreshTokenEnc: string | null;
  expiresAt: Date | null;
  needsReauth: boolean;
  accountLogin: string;
};

export type TokenWrite = { accessTokenEnc: string; refreshTokenEnc: string | null; expiresAt: Date | null };

export interface ConnectionRepo {
  get(userId: string, provider: ProviderId): Promise<StoredConnection | null>;
  upsert(
    userId: string,
    provider: ProviderId,
    data: TokenWrite & { scopes: string[]; profile: AccountProfile; keepRefreshIfNull: boolean },
  ): Promise<void>;
  /** Writes [data] only while the row still has [expectRefreshEnc]. True when this call won. */
  swapTokens(userId: string, provider: ProviderId, expectRefreshEnc: string, data: TokenWrite): Promise<boolean>;
  flagReauth(userId: string, provider: ProviderId): Promise<void>;
  touch(userId: string, provider: ProviderId): Promise<void>;
  remove(userId: string, provider: ProviderId): Promise<boolean>;
}

export type TokenDeps = {
  repo: ConnectionRepo;
  fetch: typeof fetch;
  now: () => number;
  encrypt: (plain: string) => string;
  decrypt: (stored: string) => string;
  providers?: Record<ProviderId, OAuthProvider>;
};

/** Refresh this long before the access token runs out. */
export const REFRESH_EARLY_MS = 5 * 60_000;
const TIMEOUT_MS = 10_000;

export const notConnected = (p: OAuthProvider) =>
  new AppError(404, "connector_not_connected", `${p.name} is not connected. Connect it in Apps.`);
export const needsReauth = (p: OAuthProvider) =>
  new AppError(401, "connector_reauth", `${p.name} access expired or was revoked. Reconnect it in Apps.`);
export const providerNotConfigured = (p: OAuthProvider) =>
  new AppError(503, "connector_not_configured", `${p.name} is not set up on this server.`);

export function createTokenManager(deps: TokenDeps) {
  const providers = deps.providers ?? PROVIDERS;
  const inflight = new Map<string, Promise<string>>();

  const expiry = (grant: TokenGrant) => (grant.expiresIn > 0 ? new Date(deps.now() + grant.expiresIn * 1000) : null);

  /** Stores a fresh grant (connect / reconnect); clears any Reconnect flag. */
  async function save(userId: string, provider: ProviderId, grant: TokenGrant, profile: AccountProfile): Promise<void> {
    await deps.repo.upsert(userId, provider, {
      accessTokenEnc: deps.encrypt(grant.accessToken),
      refreshTokenEnc: grant.refreshToken ? deps.encrypt(grant.refreshToken) : null,
      // Google omits the refresh token when consent was not asked again: keep the old one.
      keepRefreshIfNull: true,
      expiresAt: expiry(grant),
      scopes: grant.scopes,
      profile,
    });
    log.info("connector connected", { provider });
  }

  async function refresh(userId: string, p: OAuthProvider, row: StoredConnection): Promise<string> {
    const oldRefreshEnc = row.refreshTokenEnc!;
    let res: { status: number; json: Record<string, unknown> };
    try {
      res = await callToken(p, { grant_type: "refresh_token", refresh_token: deps.decrypt(oldRefreshEnc) }, { fetch: deps.fetch }, TIMEOUT_MS);
    } catch (e) {
      log.warn("connector refresh failed", { provider: p.id, message: (e as Error).message.slice(0, 80) });
      return stillValid(p, row);
    }
    const grant = res.status < 300 ? parseGrant(res.json) : null;
    if (!grant) {
      const code = String(res.json.error ?? res.status).slice(0, 40);
      log.warn("connector refresh rejected", { provider: p.id, error: code });
      // The grant is gone (revoked, expired refresh token): ask for Reconnect.
      if (res.status === 400 || res.status === 401) {
        await deps.repo.flagReauth(userId, p.id);
        throw needsReauth(p);
      }
      return stillValid(p, row);
    }
    const write: TokenWrite = {
      accessTokenEnc: deps.encrypt(grant.accessToken),
      refreshTokenEnc: grant.refreshToken ? deps.encrypt(grant.refreshToken) : oldRefreshEnc,
      expiresAt: expiry(grant),
    };
    // Compare-and-swap: another instance may have rotated the refresh token meanwhile.
    if (await deps.repo.swapTokens(userId, p.id, oldRefreshEnc, write)) return grant.accessToken;
    const now = await deps.repo.get(userId, p.id);
    if (!now) throw notConnected(p);
    return deps.decrypt(now.accessTokenEnc);
  }

  /** The current token while it has not expired yet (refresh failed transiently). */
  function stillValid(p: OAuthProvider, row: StoredConnection): string {
    if (row.expiresAt && row.expiresAt.getTime() <= deps.now()) {
      throw new AppError(503, "connector_unavailable", `Could not reach ${p.name}. Try again in a moment.`, true);
    }
    return deps.decrypt(row.accessTokenEnc);
  }

  /** A usable access token for [userId]'s [provider] connection. */
  async function accessToken(userId: string, provider: ProviderId): Promise<string> {
    const p = providers[provider];
    const row = await deps.repo.get(userId, provider);
    if (!row) throw notConnected(p);
    if (row.needsReauth) throw needsReauth(p);
    void deps.repo.touch(userId, provider).catch(() => undefined);
    const due = row.expiresAt && row.expiresAt.getTime() - deps.now() < REFRESH_EARLY_MS;
    if (!due) return deps.decrypt(row.accessTokenEnc);
    if (!row.refreshTokenEnc || !p.refresh) return stillValid(p, row);
    const key = `${userId}:${provider}`;
    let job = inflight.get(key);
    if (!job) {
      job = refresh(userId, p, row).finally(() => inflight.delete(key));
      inflight.set(key, job);
    }
    return job;
  }

  /** The provider answered 401 to a call with this token: Reconnect. */
  async function rejected(userId: string, provider: ProviderId): Promise<never> {
    await deps.repo.flagReauth(userId, provider).catch(() => undefined);
    throw needsReauth(providers[provider]);
  }

  /** Revokes at the provider when possible, then deletes the row. */
  async function disconnect(userId: string, provider: ProviderId): Promise<{ deleted: boolean; revoked: boolean }> {
    const p = providers[provider];
    const row = await deps.repo.get(userId, provider);
    if (!row) return { deleted: false, revoked: false };
    let revoked = false;
    if (p.revoke) {
      try {
        // Google: revoking the refresh token ends the whole grant.
        const token = deps.decrypt(row.refreshTokenEnc ?? row.accessTokenEnc);
        revoked = await p.revoke(token, { fetch: deps.fetch, clientId: p.clientId(), clientSecret: p.clientSecret() });
      } catch (e) {
        log.warn("connector revoke failed", { provider, message: (e as Error).message.slice(0, 80) });
      }
    }
    const deleted = await deps.repo.remove(userId, provider);
    log.info("connector disconnected", { provider, revoked });
    return { deleted, revoked };
  }

  return { save, accessToken, rejected, disconnect };
}

export type TokenManager = ReturnType<typeof createTokenManager>;

// ---- Prisma repository ------------------------------------------------------

const key = (userId: string, provider: string) => ({ userId_provider: { userId, provider } });

export const prismaConnectionRepo: ConnectionRepo = {
  async get(userId, provider) {
    return db().connection.findUnique({
      where: key(userId, provider),
      select: { accessTokenEnc: true, refreshTokenEnc: true, expiresAt: true, needsReauth: true, accountLogin: true },
    });
  },
  async upsert(userId, provider, d) {
    const base = {
      accountLogin: d.profile.login.slice(0, 200),
      accountId: d.profile.id.slice(0, 200),
      accountName: d.profile.name?.slice(0, 200) ?? null,
      accountEmail: d.profile.email?.slice(0, 320) ?? null,
      avatarUrl: d.profile.avatarUrl?.slice(0, 2000) ?? null,
      meta: d.profile.meta as object,
      scopes: d.scopes,
      accessTokenEnc: d.accessTokenEnc,
      expiresAt: d.expiresAt,
      needsReauth: false,
    };
    await db().connection.upsert({
      where: key(userId, provider),
      create: { userId, provider, ...base, refreshTokenEnc: d.refreshTokenEnc },
      update: { ...base, ...(d.refreshTokenEnc || !d.keepRefreshIfNull ? { refreshTokenEnc: d.refreshTokenEnc } : {}) },
    });
  },
  async swapTokens(userId, provider, expectRefreshEnc, data) {
    const n = await db().connection.updateMany({ where: { userId, provider, refreshTokenEnc: expectRefreshEnc }, data });
    return n.count === 1;
  },
  async flagReauth(userId, provider) {
    await db().connection.updateMany({ where: { userId, provider }, data: { needsReauth: true } });
  },
  async touch(userId, provider) {
    await db().connection.updateMany({ where: { userId, provider }, data: { lastUsedAt: new Date() } });
  },
  async remove(userId, provider) {
    const n = await db().connection.deleteMany({ where: { userId, provider } });
    return n.count > 0;
  },
};

export const connectorTokens = createTokenManager({
  repo: prismaConnectionRepo,
  fetch: (...a) => fetch(...a),
  now: () => Date.now(),
  encrypt: (plain) => encryptSecret(plain),
  decrypt: (stored) => decryptSecret(stored),
});

/**
 * Calls a provider API with the user's token; a 401 flags the connection for
 * Reconnect, a 429 becomes a retryable rate-limit error.
 */
export async function providerFetch(
  userId: string,
  provider: ProviderId,
  url: string,
  init: RequestInit & { timeoutMs?: number } = {},
  tokens: TokenManager = connectorTokens,
  f: typeof fetch = fetch,
): Promise<Response> {
  const token = await tokens.accessToken(userId, provider);
  const { timeoutMs, ...rest } = init;
  const headers = new Headers(rest.headers);
  headers.set("Authorization", `Bearer ${token}`);
  let res: Response;
  try {
    res = await f(url, { ...rest, headers, signal: rest.signal ?? AbortSignal.timeout(timeoutMs ?? 15_000) });
  } catch (e) {
    if ((e as Error).name === "AbortError" || (e as Error).name === "TimeoutError") {
      throw new AppError(504, "connector_timeout", `${PROVIDERS[provider].name} took too long to answer.`, true);
    }
    throw new AppError(502, "connector_unavailable", `Could not reach ${PROVIDERS[provider].name}.`, true);
  }
  if (res.status === 401) return tokens.rejected(userId, provider);
  if (res.status === 429) throw new AppError(429, "connector_rate_limited", `${PROVIDERS[provider].name} is busy. Try again in a minute.`, true);
  return res;
}
