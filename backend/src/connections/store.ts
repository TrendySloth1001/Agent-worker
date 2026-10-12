import { config } from "../config.js";
import { db } from "../db/prisma.js";
import { log } from "../util/logger.js";
import { decryptSecret, encryptSecret } from "./crypto.js";
import { DeviceFlows, missingGithubScopes, type ConnectionRow } from "./deviceFlow.js";

/** Connections as the app sees them: never any token. */
export type ConnectionSummary = {
  provider: string;
  accountLogin: string;
  accountId: string;
  avatarUrl: string | null;
  scopes: string[];
  /** Scopes sparky asks for that this grant lacks; reconnecting adds them. */
  missingScopes: string[];
  expiresAt: string | null;
  createdAt: string;
  updatedAt: string;
  lastUsedAt: string | null;
  /** Account name / email (Google Drive, Notion); null for GitHub. */
  accountName: string | null;
  accountEmail: string | null;
  /** Non-secret provider extras (Notion workspace name and icon). */
  meta: Record<string, unknown>;
  /** The provider rejected the token: the app offers Reconnect. */
  needsReauth: boolean;
};

const summary = (c: {
  provider: string;
  accountLogin: string;
  accountId: string;
  avatarUrl: string | null;
  scopes: string[];
  expiresAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
  lastUsedAt: Date | null;
  accountName?: string | null;
  accountEmail?: string | null;
  meta?: unknown;
  needsReauth?: boolean;
}): ConnectionSummary => ({
  provider: c.provider,
  accountLogin: c.accountLogin,
  accountId: c.accountId,
  avatarUrl: c.avatarUrl,
  scopes: c.scopes,
  missingScopes: c.provider === "github" ? missingGithubScopes(c.scopes) : [],
  expiresAt: c.expiresAt?.toISOString() ?? null,
  createdAt: c.createdAt.toISOString(),
  updatedAt: c.updatedAt.toISOString(),
  lastUsedAt: c.lastUsedAt?.toISOString() ?? null,
  accountName: c.accountName ?? null,
  accountEmail: c.accountEmail ?? null,
  meta: c.meta && typeof c.meta === "object" && !Array.isArray(c.meta) ? (c.meta as Record<string, unknown>) : {},
  needsReauth: c.needsReauth ?? false,
});

export async function listConnections(userId: string): Promise<ConnectionSummary[]> {
  const rows = await db().connection.findMany({
    where: { userId },
    orderBy: { createdAt: "asc" },
    select: {
      provider: true,
      accountLogin: true,
      accountId: true,
      avatarUrl: true,
      scopes: true,
      expiresAt: true,
      createdAt: true,
      updatedAt: true,
      lastUsedAt: true,
      accountName: true,
      accountEmail: true,
      meta: true,
      needsReauth: true,
    },
  });
  return rows.map(summary);
}

export async function saveGithubConnection(row: ConnectionRow): Promise<void> {
  const data = {
    accountLogin: row.login,
    accountId: row.id,
    avatarUrl: row.avatarUrl,
    scopes: row.scopes,
    accessTokenEnc: row.accessTokenEnc,
    refreshTokenEnc: row.refreshTokenEnc,
    expiresAt: row.expiresAt,
  };
  await db().connection.upsert({
    where: { userId_provider: { userId: row.userId, provider: "github" } },
    create: { userId: row.userId, provider: "github", ...data },
    update: data,
  });
  forgetGithubAuth(row.userId);
  log.info("github connected", { login: row.login });
}

// ---- the decrypted token, cached briefly per user ------------------------

export type GithubUserAuth = { token: string; login: string; scopes: string[] };
const AUTH_TTL_MS = 60_000;
const TOUCH_EVERY_MS = 5 * 60_000;
const authCache = new Map<string, { at: number; value: GithubUserAuth | null }>();
const touched = new Map<string, number>();

export function forgetGithubAuth(userId: string) {
  authCache.delete(userId);
}

/** The user's GitHub token, or null when not connected (or expired). */
export async function githubAuthFor(userId: string): Promise<GithubUserAuth | null> {
  const hit = authCache.get(userId);
  if (hit && Date.now() - hit.at < AUTH_TTL_MS) return hit.value;
  let value: GithubUserAuth | null = null;
  let row = await db().connection.findUnique({ where: { userId_provider: { userId, provider: "github" } } });
  // Expiring tokens (the OAuth app has "expire user access tokens" on) are
  // renewed with the refresh token shortly before they run out.
  if (row?.expiresAt && row.refreshTokenEnc && row.expiresAt.getTime() - Date.now() < REFRESH_EARLY_MS) {
    row = (await refreshGithubToken(userId, row.refreshTokenEnc)) ?? row;
  }
  if (row && !(row.expiresAt && row.expiresAt.getTime() <= Date.now())) {
    try {
      value = { token: decryptSecret(row.accessTokenEnc), login: row.accountLogin, scopes: row.scopes };
    } catch (e) {
      log.warn("github connection unreadable (CONNECTIONS_KEY changed?)", { message: (e as Error).message.slice(0, 80) });
    }
  }
  authCache.set(userId, { at: Date.now(), value });
  if (value && Date.now() - (touched.get(userId) ?? 0) > TOUCH_EVERY_MS) {
    touched.set(userId, Date.now());
    void db()
      .connection.update({ where: { userId_provider: { userId, provider: "github" } }, data: { lastUsedAt: new Date() } })
      .catch(() => {});
  }
  return value;
}

const REFRESH_EARLY_MS = 5 * 60_000;
const refreshing = new Map<string, Promise<Awaited<ReturnType<typeof doRefresh>>>>();

/** One refresh per user at a time; concurrent callers share it. */
function refreshGithubToken(userId: string, refreshTokenEnc: string) {
  let p = refreshing.get(userId);
  if (!p) {
    p = doRefresh(userId, refreshTokenEnc).finally(() => refreshing.delete(userId));
    refreshing.set(userId, p);
  }
  return p;
}

/** Swaps the refresh token for a new access/refresh pair. Null when it can't. */
async function doRefresh(userId: string, refreshTokenEnc: string) {
  const { clientId, clientSecret } = config.githubOAuth;
  if (!clientId || !clientSecret) return null;
  try {
    const res = await fetch("https://github.com/login/oauth/access_token", {
      method: "POST",
      headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        grant_type: "refresh_token",
        refresh_token: decryptSecret(refreshTokenEnc),
      }),
      signal: AbortSignal.timeout(10_000),
    });
    const j = (await res.json().catch(() => ({}))) as Record<string, unknown>;
    if (!res.ok || typeof j.access_token !== "string") {
      log.warn("github token refresh failed", { error: String(j.error ?? res.status).slice(0, 60) });
      return null;
    }
    const expiresIn = Number(j.expires_in);
    return await db().connection.update({
      where: { userId_provider: { userId, provider: "github" } },
      data: {
        accessTokenEnc: encryptSecret(j.access_token),
        refreshTokenEnc: typeof j.refresh_token === "string" ? encryptSecret(j.refresh_token) : refreshTokenEnc,
        expiresAt: expiresIn > 0 ? new Date(Date.now() + expiresIn * 1000) : null,
      },
    });
  } catch (e) {
    log.warn("github token refresh failed", { message: (e as Error).message.slice(0, 80) });
    return null;
  }
}

/**
 * Removes the user's GitHub connection. With GITHUB_OAUTH_CLIENT_SECRET set the
 * grant is also revoked on GitHub; otherwise only the local copy is deleted.
 */
export async function deleteGithubConnection(userId: string): Promise<{ deleted: boolean; revokedOnGithub: boolean }> {
  const row = await db().connection.findUnique({ where: { userId_provider: { userId, provider: "github" } } });
  if (!row) return { deleted: false, revokedOnGithub: false };
  let revokedOnGithub = false;
  const { clientId, clientSecret } = config.githubOAuth;
  if (clientId && clientSecret) {
    try {
      const token = decryptSecret(row.accessTokenEnc);
      const res = await fetch(`https://api.github.com/applications/${encodeURIComponent(clientId)}/grant`, {
        method: "DELETE",
        headers: {
          Authorization: `Basic ${Buffer.from(`${clientId}:${clientSecret}`).toString("base64")}`,
          Accept: "application/vnd.github+json",
          "User-Agent": "AgentWorker",
          "X-GitHub-Api-Version": "2022-11-28",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ access_token: token }),
        signal: AbortSignal.timeout(10_000),
      });
      revokedOnGithub = res.status === 204 || res.status === 404;
      if (!revokedOnGithub) log.warn("github grant revoke failed", { status: res.status });
    } catch (e) {
      log.warn("github grant revoke failed", { message: (e as Error).message.slice(0, 80) });
    }
  }
  await db().connection.deleteMany({ where: { userId, provider: "github" } });
  forgetGithubAuth(userId);
  return { deleted: true, revokedOnGithub };
}

/** The token stopped working on GitHub (revoked there): forget it. */
export async function dropRevokedGithub(userId: string) {
  forgetGithubAuth(userId);
  await db()
    .connection.deleteMany({ where: { userId, provider: "github" } })
    .catch(() => {});
  log.info("github connection dropped: token rejected");
}

export const deviceFlows = new DeviceFlows({
  clientId: () => config.githubOAuth.clientId,
  fetch: (...a) => fetch(...a),
  now: () => Date.now(),
  encrypt: (plain) => encryptSecret(plain),
  save: saveGithubConnection,
});
