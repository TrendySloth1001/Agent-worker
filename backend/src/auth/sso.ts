import { db, tx, type Tx } from "../db/prisma.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { createAccount, issue, normalizeEmail, type Tokens, type UserRow } from "./service.js";

/**
 * "Continue with GitHub / Google": who a provider says the person is, and how
 * that maps to a sparky account (table auth_identities).
 *
 * Resolution, in order:
 *  (a) an identity (provider, providerUserId) is linked: sign in to its account;
 *  (b) an account has the same email AND the provider verified that email:
 *      link the identity to it and sign in;
 *  (c) otherwise create an account without a password. An unverified email
 *      never links and never makes the owner; if an account already uses that
 *      email the sign-in is refused (409 email_in_use_link_from_profile) so the
 *      person links the provider from Profile instead.
 */

export type SsoProvider = "github" | "google";

export type SsoProfile = {
  provider: SsoProvider;
  /** GitHub numeric id / Google `sub`. */
  providerUserId: string;
  email: string | null;
  emailVerified: boolean;
  name: string | null;
  avatarUrl: string | null;
  /** GitHub login (display only). */
  login: string | null;
};

export type SsoOutcome = "signed_in" | "linked" | "created";

const LABEL: Record<SsoProvider, string> = { github: "GitHub", google: "Google" };

const disabled = () => new AppError(403, "account_disabled", "This account is disabled.");

/** Only https avatars are stored; anything else falls back to initials. */
const safeAvatar = (url: string | null) => (url && /^https:\/\/\S+$/.test(url) && url.length < 2000 ? url : null);

function identityData(p: SsoProfile) {
  return {
    provider: p.provider,
    providerUserId: p.providerUserId,
    email: p.email ? normalizeEmail(p.email) : null,
    emailVerified: p.emailVerified,
    login: p.login,
  };
}

/** Finds or creates the account for [p] inside transaction [c]. */
export async function resolveSsoUser(c: Tx, p: SsoProfile): Promise<{ user: UserRow; outcome: SsoOutcome }> {
  if (!p.providerUserId) throw new AppError(400, "sso_failed", `${LABEL[p.provider]} returned no account id.`);
  // (a) already linked.
  const linked = await c.authIdentity.findUnique({
    where: { provider_providerUserId: { provider: p.provider, providerUserId: p.providerUserId } },
    include: { user: true },
  });
  if (linked) {
    if (linked.user.disabled) throw disabled();
    // Keep the display bits current (GitHub logins can be renamed).
    const fresh = identityData(p);
    if (fresh.login !== linked.login || fresh.email !== linked.email || fresh.emailVerified !== linked.emailVerified) {
      await c.authIdentity.update({ where: { id: linked.id }, data: { login: fresh.login, email: fresh.email, emailVerified: fresh.emailVerified } });
    }
    return { user: linked.user, outcome: "signed_in" };
  }

  if (!p.email) {
    throw new AppError(
      400,
      "no_email",
      `Your ${LABEL[p.provider]} account has no email address sparky can read. Add one there, or create an account with email.`,
    );
  }
  const email = normalizeEmail(p.email);
  const existing = await c.user.findUnique({ where: { email } });

  if (existing) {
    // (b) same email, vouched for by the provider.
    if (p.emailVerified && (await trustsEmail(c, existing))) {
      if (existing.disabled) throw disabled();
      await c.authIdentity.create({ data: { userId: existing.id, ...identityData(p) } });
      log.info("sso identity linked by email", { provider: p.provider });
      return { user: existing, outcome: "linked" };
    }
    throw new AppError(
      409,
      "email_in_use_link_from_profile",
      `An account with ${email} already exists. Sign in to it, then link ${LABEL[p.provider]} from Profile.`,
    );
  }

  // (c) new account, no password.
  const name = (p.name ?? p.login ?? email.split("@")[0]).trim().slice(0, 60) || email.split("@")[0];
  const user = await createAccount(c, { email, passwordHash: null, name, avatarUrl: safeAvatar(p.avatarUrl), mayOwn: p.emailVerified });
  await c.authIdentity.create({ data: { userId: user.id, ...identityData(p) } });
  log.info("account created with sso", { provider: p.provider, role: user.role, verified: p.emailVerified });
  return { user, outcome: "created" };
}

/**
 * Whether an account's email is a safe match for a verified provider email.
 * Not when the account itself was made from an unverified provider email and
 * has nothing else (no password, no verified identity): that could be someone
 * squatting the address before its owner signs in.
 */
async function trustsEmail(c: Tx, u: UserRow): Promise<boolean> {
  if (u.passwordHash !== null) return true;
  const ids = await c.authIdentity.findMany({ where: { userId: u.id }, select: { emailVerified: true, email: true } });
  return ids.length === 0 || ids.some((i) => i.emailVerified && i.email === normalizeEmail(u.email));
}

/** Sign-in with [p] inside [c]: resolve, stamp the login, start a session. */
export async function ssoSignInTx(c: Tx, p: SsoProfile, device: string | null): Promise<{ user: UserRow; tokens: Tokens; outcome: SsoOutcome }> {
  const { user, outcome } = await resolveSsoUser(c, p);
  const updated = await c.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } });
  const { rowId: _row, ...tokens } = await issue(c, updated, null, device);
  return { user: updated, tokens, outcome };
}

export async function ssoSignIn(p: SsoProfile, device: string | null) {
  return tx((c) => ssoSignInTx(c, p, device));
}

// ---- linked sign-in methods (Profile) -----------------------------------

export type IdentitySummary = {
  id: string;
  provider: SsoProvider;
  email: string | null;
  login: string | null;
  createdAt: string;
};

const summary = (i: { id: string; provider: string; email: string | null; login: string | null; createdAt: Date }): IdentitySummary => ({
  id: i.id,
  provider: i.provider as SsoProvider,
  email: i.email,
  login: i.login,
  createdAt: i.createdAt.toISOString(),
});

/** Adds [p] to signed-in user [userId] (Profile → LINK). */
export async function linkIdentityTx(c: Tx, userId: string, p: SsoProfile): Promise<IdentitySummary> {
  if (!p.providerUserId) throw new AppError(400, "sso_failed", `${LABEL[p.provider]} returned no account id.`);
  const taken = await c.authIdentity.findUnique({
    where: { provider_providerUserId: { provider: p.provider, providerUserId: p.providerUserId } },
  });
  if (taken) {
    if (taken.userId !== userId) {
      throw new AppError(409, "identity_in_use", `This ${LABEL[p.provider]} account is already linked to another sparky account.`);
    }
    const row = await c.authIdentity.update({ where: { id: taken.id }, data: { login: p.login, email: identityData(p).email, emailVerified: p.emailVerified } });
    return summary(row);
  }
  const row = await c.authIdentity.create({ data: { userId, ...identityData(p) } });
  log.info("sso identity linked from profile", { provider: p.provider });
  return summary(row);
}

export async function linkIdentity(userId: string, p: SsoProfile): Promise<IdentitySummary> {
  return tx((c) => linkIdentityTx(c, userId, p));
}

export async function signInMethods(userId: string): Promise<{ hasPassword: boolean; identities: IdentitySummary[] }> {
  const u = await db().user.findUnique({
    where: { id: userId },
    select: { passwordHash: true, identities: { orderBy: { createdAt: "asc" } } },
  });
  if (!u) throw new AppError(401, "unauthorized", "Session expired");
  return { hasPassword: u.passwordHash !== null, identities: u.identities.map(summary) };
}

/** Removes one linked method; the last way in (password or identity) stays. */
export async function unlinkIdentity(userId: string, identityId: string): Promise<void> {
  await tx(async (c) => {
    // Raw: lock the user so two unlinks cannot both pass the "not the last" check.
    await c.$queryRaw`SELECT 1 FROM users WHERE id = ${userId}::uuid FOR UPDATE`;
    const u = await c.user.findUnique({ where: { id: userId }, select: { passwordHash: true, identities: { select: { id: true } } } });
    if (!u || !u.identities.some((i) => i.id === identityId)) throw new AppError(404, "not_found", "Sign-in method not found");
    const methods = u.identities.length + (u.passwordHash !== null ? 1 : 0);
    if (methods <= 1) {
      throw new AppError(409, "last_sign_in_method", "This is your only way to sign in. Set a password or link another account first.");
    }
    await c.authIdentity.delete({ where: { id: identityId } });
  });
}
