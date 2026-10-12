import { config } from "../config.js";
import { encryptSecret } from "../connections/crypto.js";
import {
  connectionRow,
  fetchGithubEmails,
  fetchGithubUser,
  GithubDeviceFlow,
  pickGithubEmail,
  type ConnectionRow,
  type DeviceGrant,
  type GithubEmail,
  type GithubUser,
} from "../connections/deviceFlow.js";
import { saveGithubConnection } from "../connections/store.js";
import { log } from "../util/logger.js";
import type { Tokens, UserRow } from "./service.js";
import { linkIdentity, ssoSignIn, type IdentitySummary, type SsoOutcome, type SsoProfile } from "./sso.js";

/**
 * "Continue with GitHub" over the device flow (no hosting, no callback URL).
 * Signed out (owner null) it signs in or creates the account; signed in
 * (owner = user id, Profile → LINK) it links GitHub to that account. The
 * grant only becomes the user's GitHub connection when it carries repo access
 * (e.g. GitHub kept an earlier, wider approval).
 */

/**
 * Sign-in only asks who you are. Repo access is asked for separately, when
 * the user connects GitHub (Apps, or the GitHub screen), with GITHUB_SCOPES.
 */
export const GITHUB_SSO_SCOPES = "read:user user:email";

export type GithubSsoMeta = { device: string | null };

export type GithubSsoResult =
  | { kind: "session"; user: UserRow; tokens: Tokens; outcome: SsoOutcome; login: string }
  | { kind: "linked"; identity: IdentitySummary };

export type GithubSsoDeps = {
  clientId: () => string | undefined;
  fetch: typeof fetch;
  now: () => number;
  signIn: (p: SsoProfile, device: string | null) => Promise<{ user: UserRow; tokens: Tokens; outcome: SsoOutcome }>;
  link: (userId: string, p: SsoProfile) => Promise<IdentitySummary>;
  encrypt: (plain: string) => string;
  saveConnection: (row: ConnectionRow) => Promise<void>;
};

export function githubProfile(u: GithubUser, emails: GithubEmail[]): SsoProfile {
  const picked = pickGithubEmail(emails, u.publicEmail);
  return {
    provider: "github",
    providerUserId: u.id,
    email: picked?.email ?? null,
    emailVerified: picked?.verified ?? false,
    name: u.name ?? u.login,
    avatarUrl: u.avatarUrl,
    login: u.login,
  };
}

/** Who [grant] belongs to: the GitHub user and the sign-in profile (with the best email). */
export async function githubGrantProfile(f: typeof fetch, grant: DeviceGrant): Promise<{ u: GithubUser; profile: SsoProfile }> {
  const u = await fetchGithubUser(f, grant.accessToken, grant.scope);
  return { u, profile: githubProfile(u, await fetchGithubEmails(f, grant.accessToken)) };
}

/**
 * Saves [grant] as [userId]'s GitHub connection. After a sign-in or link a
 * failure (e.g. no CONNECTIONS_KEY) only costs the connection; the user can
 * still CONNECT later.
 */
export async function saveGrantConnection(
  deps: Pick<GithubSsoDeps, "encrypt" | "now" | "saveConnection">,
  u: GithubUser,
  userId: string,
  grant: DeviceGrant,
): Promise<boolean> {
  // A sign-in grant without repo access is not a connection; never let it
  // replace one that has it.
  if (!grant.scope.split(/[\s,]+/).includes("repo")) return false;
  try {
    await deps.saveConnection(connectionRow(u, userId, grant, deps));
    return true;
  } catch (e) {
    log.warn("github connection not saved after sign-in", { message: (e as Error).message.slice(0, 80) });
    return false;
  }
}

export function createGithubSso(deps: GithubSsoDeps) {
  const complete = async (grant: DeviceGrant, flow: { owner: string | null; meta: GithubSsoMeta }): Promise<GithubSsoResult> => {
    const { u, profile } = await githubGrantProfile(deps.fetch, grant);
    let userId: string;
    let result: GithubSsoResult;
    if (flow.owner) {
      result = { kind: "linked", identity: await deps.link(flow.owner, profile) };
      userId = flow.owner;
    } else {
      const s = await deps.signIn(profile, flow.meta.device);
      result = { kind: "session", ...s, login: u.login };
      userId = s.user.id;
    }
    // Connected at once.
    await saveGrantConnection(deps, u, userId, grant);
    return result;
  };
  return new GithubDeviceFlow<GithubSsoResult, GithubSsoMeta>({
    clientId: deps.clientId,
    fetch: deps.fetch,
    now: deps.now,
    scope: GITHUB_SSO_SCOPES,
    complete,
    once: true,
  });
}

export const githubSso = createGithubSso({
  clientId: () => config.githubOAuth.clientId,
  fetch: (...a) => fetch(...a),
  now: () => Date.now(),
  signIn: ssoSignIn,
  link: linkIdentity,
  encrypt: (plain) => encryptSecret(plain),
  saveConnection: saveGithubConnection,
});
