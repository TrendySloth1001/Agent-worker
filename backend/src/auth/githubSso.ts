import { config } from "../config.js";
import { encryptSecret } from "../connections/crypto.js";
import {
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
 * (owner = user id, Profile → LINK) it links GitHub to that account. Either
 * way the same grant becomes the user's GitHub connection, so they are
 * connected at once. Scopes cover both sign-in (read:user user:email) and the
 * connection (repo read:org).
 */

export const GITHUB_SSO_SCOPES = "repo read:user user:email read:org";

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

export function createGithubSso(deps: GithubSsoDeps) {
  const complete = async (grant: DeviceGrant, flow: { owner: string | null; meta: GithubSsoMeta }): Promise<GithubSsoResult> => {
    const u = await fetchGithubUser(deps.fetch, grant.accessToken, grant.scope);
    const profile = githubProfile(u, await fetchGithubEmails(deps.fetch, grant.accessToken));
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
    // Connected at once. A failure here (e.g. no CONNECTIONS_KEY) only costs
    // the connection; the user can still CONNECT later.
    try {
      await deps.saveConnection({
        login: u.login,
        id: u.id,
        avatarUrl: u.avatarUrl,
        scopes: u.scopes,
        userId,
        accessTokenEnc: deps.encrypt(grant.accessToken),
        refreshTokenEnc: grant.refreshToken ? deps.encrypt(grant.refreshToken) : null,
        expiresAt: grant.expiresIn > 0 ? new Date(deps.now() + grant.expiresIn * 1000) : null,
      });
    } catch (e) {
      log.warn("github connection not saved after sign-in", { message: (e as Error).message.slice(0, 80) });
    }
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
