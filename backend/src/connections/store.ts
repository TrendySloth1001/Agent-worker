import { config } from "../config.js";
import { db } from "../db/prisma.js";
import { log } from "../util/logger.js";
import { decryptSecret, encryptSecret } from "./crypto.js";
import { DeviceFlows, type ConnectionRow } from "./deviceFlow.js";

/** Connections as the app sees them: never any token. */
export type ConnectionSummary = {
  provider: string;
  accountLogin: string;
  accountId: string;
  avatarUrl: string | null;
  scopes: string[];
  expiresAt: string | null;
  createdAt: string;
  updatedAt: string;
  lastUsedAt: string | null;
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
}): ConnectionSummary => ({
  provider: c.provider,
  accountLogin: c.accountLogin,
  accountId: c.accountId,
  avatarUrl: c.avatarUrl,
  scopes: c.scopes,
  expiresAt: c.expiresAt?.toISOString() ?? null,
  createdAt: c.createdAt.toISOString(),
  updatedAt: c.updatedAt.toISOString(),
  lastUsedAt: c.lastUsedAt?.toISOString() ?? null,
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
  const row = await db().connection.findUnique({ where: { userId_provider: { userId, provider: "github" } } });
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
