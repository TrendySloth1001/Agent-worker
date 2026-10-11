import { AsyncLocalStorage } from "node:async_hooks";
import type { NextFunction, Request, Response } from "express";
import { AppError } from "../util/errors.js";

export type Role = "owner" | "user";

/**
 * The caller of a request. `id` is null only for the API_TOKEN dev bypass
 * before the owner account exists; it then sees the not-yet-claimed rows
 * (user_id IS NULL). SQL compares with `user_id IS NOT DISTINCT FROM $n`.
 */
export type AuthUser = { id: string | null; role: Role; sid: string | null; bypass: boolean };

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

const store = new AsyncLocalStorage<AuthUser>();

/** Runs the rest of the request with [user] as the ambient caller. */
export function runAs(user: AuthUser, next: NextFunction): void {
  store.run(user, next);
}

/** The caller of the current request (from deep code paths like retrieval). */
export function currentUser(): AuthUser | undefined {
  return store.getStore();
}

/** The caller, or 401. For route handlers behind requireUser. */
export function userOf(req: Request): AuthUser {
  if (!req.user) throw new AppError(401, "unauthorized", "Sign in required");
  return req.user;
}

export function isOwnerRequest(): boolean {
  return currentUser()?.role === "owner";
}

export function requireOwner(req: Request, _res: Response, next: NextFunction): void {
  if (req.user?.role === "owner") return next();
  next(new AppError(403, "forbidden", "Only the owner can use this"));
}

/**
 * Ownership filter params for the current request: `[unscoped, userId]`.
 * Use as `($a::boolean OR t.user_id IS NOT DISTINCT FROM $b::uuid)`.
 * Unscoped only outside any request (background jobs, health).
 */
export function ownerFilter(): [boolean, string | null] {
  const u = currentUser();
  return u ? [false, u.id] : [true, null];
}
