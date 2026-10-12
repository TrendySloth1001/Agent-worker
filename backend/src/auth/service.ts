import { randomUUID, timingSafeEqual } from "node:crypto";
import type { NextFunction, Request, Response } from "express";
import { hash, verify } from "@node-rs/argon2";
import { config } from "../config.js";
import { db, isDbUp, tx, type Tx } from "../db/prisma.js";
import type { User } from "../generated/prisma/client.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { runAs, type AuthUser, type Role } from "./context.js";
import { hashToken, newRefreshToken, signAccess, verifyAccess } from "./jwt.js";

export type UserRow = User;

export const publicUser = (u: UserRow) => ({
  id: u.id,
  email: u.email,
  name: u.name,
  avatarUrl: u.avatarUrl,
  role: u.role as Role,
  createdAt: u.createdAt.toISOString(),
  lastLoginAt: u.lastLoginAt?.toISOString() ?? null,
  /** False for accounts made with GitHub/Google until they set a password. */
  hasPassword: u.passwordHash !== null,
  /** True once the app's first-run tour was finished or skipped (any device). */
  onboarded: u.onboardedAt !== null,
});

/**
 * The `onboardedAt` change for PATCH /auth/me `onboarded`: true keeps the
 * first time the tour was done, false clears it so the tour shows again.
 */
export function onboardedPatch(current: Date | null, flag: boolean | undefined, now = new Date()): { onboardedAt?: Date | null } {
  if (flag === true) return current === null ? { onboardedAt: now } : {};
  if (flag === false) return current === null ? {} : { onboardedAt: null };
  return {};
}

export const normalizeEmail =(e: string) => e.trim().toLowerCase();

/** One message for every failed sign-in, so it never reveals whether an email exists. */
export const BAD_LOGIN = "Wrong email or password";

// Hashing a dummy keeps unknown emails as slow as wrong passwords.
let dummyHash: Promise<string> | null = null;
const dummy = () => (dummyHash ??= hash("not-a-real-password-" + Math.random()));

export const hashPassword = (p: string) => hash(p);
export async function checkPassword(stored: string | null, password: string): Promise<boolean> {
  try {
    return await verify(stored ?? (await dummy()), password);
  } catch {
    return false;
  }
}

export async function getUser(id: string): Promise<UserRow | null> {
  return db().user.findUnique({ where: { id } });
}

// ---- sessions ----------------------------------------------------------

export type Tokens = {
  accessToken: string;
  accessExpiresAt: string;
  refreshToken: string;
  refreshExpiresAt: string;
  sessionId: string;
};

const refreshExpiry = () => new Date(Date.now() + config.auth.refreshTtlDays * 86_400_000);

export async function issue(c: Tx, user: { id: string; role: string }, family: { id: string; createdAt: Date } | null, device: string | null): Promise<Tokens & { rowId: string }> {
  const refreshToken = newRefreshToken();
  const expires = refreshExpiry();
  const row = await c.authSession.create({
    data: {
      familyId: family?.id ?? randomUUID(),
      userId: user.id,
      tokenHash: hashToken(refreshToken),
      device,
      // A new family starts now (column default); a rotation keeps the family's start.
      ...(family ? { familyCreatedAt: family.createdAt } : {}),
      expiresAt: expires,
    },
    select: { id: true, familyId: true },
  });
  const sid = row.familyId;
  const access = signAccess({ sub: user.id, role: user.role as Role, sid });
  return { accessToken: access.token, accessExpiresAt: access.expiresAt, refreshToken, refreshExpiresAt: expires.toISOString(), sessionId: sid, rowId: row.id };
}

export const deviceLabel = (req: Request, body?: unknown): string | null => {
  const d = (body as { device?: unknown } | undefined)?.device;
  const raw = typeof d === "string" && d.trim() ? d : req.headers["user-agent"] ?? "";
  return String(raw).replace(/[\u0000-\u001f]/g, "").trim().slice(0, 80) || null;
};

/**
 * Creates an account. Registration is open, so claiming OWNER_EMAIL also needs
 * proof: the static API_TOKEN as `ownerToken`. With no API_TOKEN configured the
 * OWNER_EMAIL cannot be claimed by password sign-up at all (fail closed).
 */
export async function register(input: { email: string; password: string; name: string; ownerToken?: string }, device: string | null) {
  const email = normalizeEmail(input.email);
  if (config.auth.ownerEmail && email === config.auth.ownerEmail && !(config.apiToken && isStaticToken(input.ownerToken ?? ""))) {
    // Fail closed: without API_TOKEN configured nobody can prove ownership by password sign-up.
    throw new AppError(400, "register_failed", "Could not create an account with these details. If you already have one, sign in.");
  }
  const passwordHash = await hashPassword(input.password);
  return tx(async (c) => {
    const existing = await c.user.findUnique({ where: { email }, select: { id: true } });
    if (existing) throw new AppError(400, "register_failed", "Could not create an account with these details. If you already have one, sign in.");
    const user = await createAccount(c, { email, passwordHash, name: input.name.trim(), avatarUrl: null, mayOwn: true });
    return { user, tokens: await issue(c, user, null, device) };
  });
}

/**
 * Inserts a user. The owner is OWNER_EMAIL when set, otherwise the very first
 * account, and only when [mayOwn] (the caller proved the email: API_TOKEN for
 * a password sign-up, a provider-verified email for GitHub/Google).
 */
export async function createAccount(
  c: Tx,
  input: { email: string; passwordHash: string | null; name: string; avatarUrl: string | null; mayOwn: boolean },
): Promise<UserRow> {
  const email = normalizeEmail(input.email);
  let owner = false;
  if (input.mayOwn) {
    const owners = await c.user.count({ where: { role: "owner" } });
    owner = owners === 0 && (config.auth.ownerEmail ? email === config.auth.ownerEmail : (await c.user.count()) === 0);
  }
  const user = await c.user.create({
    data: { email, passwordHash: input.passwordHash, name: input.name, avatarUrl: input.avatarUrl, role: owner ? "owner" : "user", lastLoginAt: new Date() },
  });
  if (owner) {
    // Data from before accounts existed belongs to the owner.
    const unclaimed = { where: { userId: null }, data: { userId: user.id } };
    const claimed = {
      conversations: (await c.conversation.updateMany(unclaimed)).count,
      files: (await c.storedFile.updateMany(unclaimed)).count,
      sources: (await c.source.updateMany(unclaimed)).count,
    };
    log.info("owner account created", claimed);
  }
  forgetOwner();
  return user;
}

const PROVIDER_LABEL: Record<string, string> = { github: "GitHub", google: "Google" };

export async function login(emailRaw: string, password: string, device: string | null) {
  const user = await db().user.findUnique({ where: { email: normalizeEmail(emailRaw) } });
  const ok = await checkPassword(user?.passwordHash ?? null, password);
  if (user && user.passwordHash === null && !user.disabled) {
    // Made with GitHub/Google and no password yet: say how to get in.
    const ids = await db().authIdentity.findMany({ where: { userId: user.id }, select: { provider: true }, distinct: ["provider"] });
    const names = ids.map((i) => PROVIDER_LABEL[i.provider] ?? i.provider);
    const via = names.length ? names.join(" or ") : "GitHub or Google";
    throw new AppError(401, "password_not_set", `This account signs in with ${via}. Use Continue with ${via}, then set a password from Profile.`);
  }
  if (!user || !ok || user.disabled) throw new AppError(401, "invalid_credentials", BAD_LOGIN);
  return tx(async (c) => {
    const updated = await c.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } });
    return { user: updated, tokens: await issue(c, user, null, device) };
  });
}

// A refresh token reused within this window after rotation is treated as a
// client race (two requests refreshing at once), not theft.
const REUSE_GRACE_MS = 20_000;

export async function refresh(token: string, device: string | null) {
  const h = hashToken(token);
  const out = await tx(async (c) => {
    // Raw: Prisma has no SELECT ... FOR UPDATE; the row lock serializes concurrent refreshes.
    await c.$queryRaw`SELECT 1 FROM auth_sessions WHERE token_hash = ${h} FOR UPDATE`;
    const s = await c.authSession.findUnique({ where: { tokenHash: h } });
    if (!s) return { error: "invalid" as const };
    if (s.revokedAt) {
      if (s.replacedBy && Date.now() - s.revokedAt.getTime() < REUSE_GRACE_MS) return { error: "race" as const };
      // Reuse of a rotated token: someone else may hold it. End the whole session.
      await c.authSession.updateMany({ where: { familyId: s.familyId, revokedAt: null }, data: { revokedAt: new Date() } });
      return { error: "reuse" as const, familyId: s.familyId, userId: s.userId };
    }
    if (s.expiresAt.getTime() <= Date.now()) return { error: "invalid" as const };
    const user = await c.user.findUnique({ where: { id: s.userId } });
    if (!user || user.disabled) return { error: "invalid" as const };
    const tokens = await issue(c, user, { id: s.familyId, createdAt: s.familyCreatedAt }, s.device ?? device);
    await c.authSession.update({ where: { id: s.id }, data: { revokedAt: new Date(), replacedBy: tokens.rowId } });
    return { user, tokens };
  });
  if ("error" in out) {
    if (out.error === "reuse") {
      log.warn("refresh token reuse, session revoked", { family: out.familyId });
      forgetUser(out.userId);
    }
    throw new AppError(401, "invalid_refresh", "Session expired, please sign in again");
  }
  return out;
}

/** Ends the session (token family) a refresh token belongs to. */
export async function revokeByRefresh(token: string): Promise<void> {
  const s = await db().authSession.findUnique({ where: { tokenHash: hashToken(token) }, select: { familyId: true, userId: true } });
  if (s) await revokeFamily(s.userId, s.familyId);
}

export async function revokeFamily(userId: string, familyId: string): Promise<boolean> {
  const r = await db().authSession.updateMany({ where: { userId, familyId, revokedAt: null }, data: { revokedAt: new Date() } });
  forgetUser(userId);
  return r.count > 0;
}

/** Ends every session of a user except [keep]. */
export async function revokeOthers(userId: string, keep: string | null): Promise<void> {
  await db().authSession.updateMany({
    where: { userId, revokedAt: null, ...(keep ? { familyId: { not: keep } } : {}) },
    data: { revokedAt: new Date() },
  });
  forgetUser(userId);
}

export async function listSessions(userId: string, current: string | null) {
  const rows = await db().authSession.findMany({
    where: { userId, revokedAt: null, expiresAt: { gt: new Date() } },
    orderBy: { createdAt: "desc" },
    select: { familyId: true, device: true, familyCreatedAt: true, createdAt: true, expiresAt: true },
  });
  return rows.map((r) => ({
    id: r.familyId,
    device: r.device,
    createdAt: r.familyCreatedAt.toISOString(),
    lastUsedAt: r.createdAt.toISOString(),
    expiresAt: r.expiresAt.toISOString(),
    current: r.familyId === current,
  }));
}

// ---- request authentication -------------------------------------------

type Check = { ok: boolean; role: Role; at: number };
const checks = new Map<string, Check>();
const CHECK_TTL_MS = 30_000;

/** Drops cached session checks, so a revoke or delete applies at once. */
export function forgetUser(userId: string): void {
  for (const k of checks.keys()) if (k.startsWith(`${userId}:`)) checks.delete(k);
}

async function sessionCheck(userId: string, sid: string, role: Role): Promise<Check> {
  const key = `${userId}:${sid}`;
  const hit = checks.get(key);
  if (hit && Date.now() - hit.at < CHECK_TTL_MS) return hit;
  // Database down: a correctly signed, unexpired token is trusted.
  if (!isDbUp()) return { ok: true, role, at: Date.now() };
  const r = await db().user.findUnique({
    where: { id: userId },
    select: {
      role: true,
      disabled: true,
      sessions: { where: { familyId: sid, revokedAt: null, expiresAt: { gt: new Date() } }, select: { id: true }, take: 1 },
    },
  });
  const check = { ok: !!r && !r.disabled && r.sessions.length > 0, role: (r?.role as Role | undefined) ?? role, at: Date.now() };
  checks.set(key, check);
  if (checks.size > 5000) checks.delete(checks.keys().next().value!);
  return check;
}

let ownerCache: { id: string | null; at: number } | null = null;
function forgetOwner() {
  ownerCache = null;
}

/** The owner's id, or null while no owner has registered. */
export async function ownerId(): Promise<string | null> {
  if (ownerCache && Date.now() - ownerCache.at < 30_000) return ownerCache.id;
  if (!isDbUp()) return null;
  const owner = await db().user.findFirst({ where: { role: "owner" }, select: { id: true } });
  ownerCache = { id: owner?.id ?? null, at: Date.now() };
  return ownerCache.id;
}

function isStaticToken(token: string): boolean {
  const want = config.apiToken;
  if (!want) return false;
  const a = Buffer.from(token);
  const b = Buffer.from(want);
  return a.length === b.length && timingSafeEqual(a, b);
}

/**
 * Accepts a valid access JWT and sets req.user. The static API_TOKEN still
 * works as an admin/dev bypass that acts as the owner account (curl tests).
 */
export async function requireUser(req: Request, _res: Response, next: NextFunction): Promise<void> {
  const h = req.headers.authorization ?? "";
  const token = h.startsWith("Bearer ") ? h.slice(7).trim() : "";
  if (!token) return next(new AppError(401, "unauthorized", "Sign in required"));
  let user: AuthUser;
  if (isStaticToken(token)) {
    user = { id: await ownerId().catch(() => null), role: "owner", sid: null, bypass: true };
  } else {
    const claims = verifyAccess(token);
    if (!claims) return next(new AppError(401, "unauthorized", "Session expired"));
    const check = await sessionCheck(claims.sub, claims.sid, claims.role);
    if (!check.ok) return next(new AppError(401, "unauthorized", "Session expired"));
    user = { id: claims.sub, role: check.role, sid: claims.sid, bypass: false };
  }
  req.user = user;
  runAs(user, next);
}
