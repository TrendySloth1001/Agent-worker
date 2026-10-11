import { timingSafeEqual } from "node:crypto";
import type { NextFunction, Request, Response } from "express";
import { hash, verify } from "@node-rs/argon2";
import type pg from "pg";
import { config } from "../config.js";
import { isDbUp, query, withTx } from "../db/pool.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { runAs, type AuthUser, type Role } from "./context.js";
import { hashToken, newRefreshToken, signAccess, verifyAccess } from "./jwt.js";

export type UserRow = {
  id: string;
  email: string;
  password_hash: string;
  name: string;
  avatar_url: string | null;
  role: Role;
  limits: Record<string, number>;
  disabled: boolean;
  created_at: Date;
  last_login_at: Date | null;
};

export const publicUser = (u: UserRow) => ({
  id: u.id,
  email: u.email,
  name: u.name,
  avatarUrl: u.avatar_url,
  role: u.role,
  createdAt: u.created_at.toISOString(),
  lastLoginAt: u.last_login_at?.toISOString() ?? null,
});

export const normalizeEmail = (e: string) => e.trim().toLowerCase();

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
  const { rows } = await query<UserRow>("SELECT * FROM users WHERE id = $1", [id]);
  return rows[0] ?? null;
}

// ---- sessions ----------------------------------------------------------

export type Tokens = {
  accessToken: string;
  accessExpiresAt: string;
  refreshToken: string;
  refreshExpiresAt: string;
  sessionId: string;
};

type Db = Pick<pg.PoolClient, "query">;

const refreshExpiry = () => new Date(Date.now() + config.auth.refreshTtlDays * 86_400_000);

async function issue(c: Db, user: { id: string; role: Role }, family: { id: string; createdAt: Date } | null, device: string | null): Promise<Tokens & { rowId: string }> {
  const refreshToken = newRefreshToken();
  const expires = refreshExpiry();
  const { rows } = await c.query<{ id: string; family_id: string }>(
    `INSERT INTO auth_sessions (family_id, user_id, token_hash, device, family_created_at, expires_at)
     VALUES (COALESCE($1::uuid, gen_random_uuid()), $2, $3, $4, COALESCE($5::timestamptz, now()), $6) RETURNING id, family_id`,
    [family?.id ?? null, user.id, hashToken(refreshToken), device, family?.createdAt ?? null, expires],
  );
  const sid = rows[0].family_id;
  const access = signAccess({ sub: user.id, role: user.role, sid });
  return { accessToken: access.token, accessExpiresAt: access.expiresAt, refreshToken, refreshExpiresAt: expires.toISOString(), sessionId: sid, rowId: rows[0].id };
}

export const deviceLabel = (req: Request, body?: unknown): string | null => {
  const d = (body as { device?: unknown } | undefined)?.device;
  const raw = typeof d === "string" && d.trim() ? d : req.headers["user-agent"] ?? "";
  return String(raw).replace(/[\u0000-\u001f]/g, "").trim().slice(0, 80) || null;
};

/**
 * Creates an account. Registration is open, so claiming OWNER_EMAIL also needs
 * proof: the static API_TOKEN as `ownerToken` (when one is configured).
 */
export async function register(input: { email: string; password: string; name: string; ownerToken?: string }, device: string | null) {
  const email = normalizeEmail(input.email);
  if (config.auth.ownerEmail && email === config.auth.ownerEmail && config.apiToken && !isStaticToken(input.ownerToken ?? "")) {
    throw new AppError(400, "register_failed", "Could not create an account with these details. If you already have one, sign in.");
  }
  const passwordHash = await hashPassword(input.password);
  return withTx(async (c) => {
    const { rows: existing } = await c.query("SELECT 1 FROM users WHERE email = $1", [email]);
    if (existing[0]) throw new AppError(400, "register_failed", "Could not create an account with these details. If you already have one, sign in.");
    // The owner: OWNER_EMAIL when set, otherwise the very first account.
    const { rows: counts } = await c.query<{ users: number; owners: number }>(
      "SELECT count(*)::int AS users, count(*) FILTER (WHERE role = 'owner')::int AS owners FROM users",
    );
    const owner = counts[0].owners === 0 && (config.auth.ownerEmail ? email === config.auth.ownerEmail : counts[0].users === 0);
    const { rows } = await c.query<UserRow>(
      `INSERT INTO users (email, password_hash, name, role, last_login_at) VALUES ($1, $2, $3, $4, now()) RETURNING *`,
      [email, passwordHash, input.name.trim(), owner ? "owner" : "user"],
    );
    const user = rows[0];
    if (owner) {
      // Data from before accounts existed belongs to the owner.
      const claimed: Record<string, number> = {};
      for (const t of ["conversations", "files", "sources"]) {
        claimed[t] = (await c.query(`UPDATE ${t} SET user_id = $1 WHERE user_id IS NULL`, [user.id])).rowCount ?? 0;
      }
      log.info("owner account created", claimed);
    }
    forgetOwner();
    return { user, tokens: await issue(c, user, null, device) };
  });
}

export async function login(emailRaw: string, password: string, device: string | null) {
  const { rows } = await query<UserRow>("SELECT * FROM users WHERE email = $1", [normalizeEmail(emailRaw)]);
  const user = rows[0];
  const ok = await checkPassword(user?.password_hash ?? null, password);
  if (!user || !ok || user.disabled) throw new AppError(401, "invalid_credentials", BAD_LOGIN);
  return withTx(async (c) => {
    const { rows: updated } = await c.query<UserRow>("UPDATE users SET last_login_at = now() WHERE id = $1 RETURNING *", [user.id]);
    return { user: updated[0], tokens: await issue(c, user, null, device) };
  });
}

// A refresh token reused within this window after rotation is treated as a
// client race (two requests refreshing at once), not theft.
const REUSE_GRACE_MS = 20_000;

export async function refresh(token: string, device: string | null) {
  const h = hashToken(token);
  const out = await withTx(async (c) => {
    const { rows } = await c.query<{
      id: string; family_id: string; user_id: string; family_created_at: Date; expires_at: Date; revoked_at: Date | null; replaced_by: string | null; device: string | null;
    }>("SELECT * FROM auth_sessions WHERE token_hash = $1 FOR UPDATE", [h]);
    const s = rows[0];
    if (!s) return { error: "invalid" as const };
    if (s.revoked_at) {
      if (s.replaced_by && Date.now() - s.revoked_at.getTime() < REUSE_GRACE_MS) return { error: "race" as const };
      // Reuse of a rotated token: someone else may hold it. End the whole session.
      await c.query("UPDATE auth_sessions SET revoked_at = now() WHERE family_id = $1 AND revoked_at IS NULL", [s.family_id]);
      return { error: "reuse" as const, familyId: s.family_id, userId: s.user_id };
    }
    if (s.expires_at.getTime() <= Date.now()) return { error: "invalid" as const };
    const { rows: users } = await c.query<UserRow>("SELECT * FROM users WHERE id = $1", [s.user_id]);
    const user = users[0];
    if (!user || user.disabled) return { error: "invalid" as const };
    const tokens = await issue(c, user, { id: s.family_id, createdAt: s.family_created_at }, s.device ?? device);
    await c.query("UPDATE auth_sessions SET revoked_at = now(), replaced_by = $2 WHERE id = $1", [s.id, tokens.rowId]);
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
  const { rows } = await query<{ family_id: string; user_id: string }>(
    "SELECT family_id, user_id FROM auth_sessions WHERE token_hash = $1",
    [hashToken(token)],
  );
  if (rows[0]) await revokeFamily(rows[0].user_id, rows[0].family_id);
}

export async function revokeFamily(userId: string, familyId: string): Promise<boolean> {
  const r = await query(
    "UPDATE auth_sessions SET revoked_at = now() WHERE user_id = $1 AND family_id = $2 AND revoked_at IS NULL",
    [userId, familyId],
  );
  forgetUser(userId);
  return r.rowCount > 0;
}

/** Ends every session of a user except [keep]. */
export async function revokeOthers(userId: string, keep: string | null): Promise<void> {
  await query(
    "UPDATE auth_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL AND ($2::uuid IS NULL OR family_id <> $2::uuid)",
    [userId, keep],
  );
  forgetUser(userId);
}

export async function listSessions(userId: string, current: string | null) {
  const { rows } = await query<{ family_id: string; device: string | null; family_created_at: Date; created_at: Date; expires_at: Date }>(
    `SELECT family_id, device, family_created_at, created_at, expires_at FROM auth_sessions
      WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > now() ORDER BY created_at DESC`,
    [userId],
  );
  return rows.map((r) => ({
    id: r.family_id,
    device: r.device,
    createdAt: r.family_created_at.toISOString(),
    lastUsedAt: r.created_at.toISOString(),
    expiresAt: r.expires_at.toISOString(),
    current: r.family_id === current,
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
  const { rows } = await query<{ role: Role; disabled: boolean; active: boolean }>(
    `SELECT u.role, u.disabled, EXISTS (
        SELECT 1 FROM auth_sessions s WHERE s.family_id = $2 AND s.user_id = u.id AND s.revoked_at IS NULL AND s.expires_at > now()
      ) AS active FROM users u WHERE u.id = $1`,
    [userId, sid],
  );
  const r = rows[0];
  const check = { ok: !!r && !r.disabled && r.active, role: r?.role ?? role, at: Date.now() };
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
  const { rows } = await query<{ id: string }>("SELECT id FROM users WHERE role = 'owner' LIMIT 1");
  ownerCache = { id: rows[0]?.id ?? null, at: Date.now() };
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
