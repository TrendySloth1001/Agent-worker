import type { NextFunction, Request, Response } from "express";
import { AppError } from "./errors.js";

/** The caller's IP (honours `trust proxy`), never empty. */
export const clientIp = (req: Request): string => req.ip ?? req.socket?.remoteAddress ?? "unknown";

/**
 * Bucket key. Authenticated routes count per user (so users behind one NAT or
 * proxy don't share a budget); anything without a user (auth routes) counts per IP.
 */
export const limitKey = (req: Request, by: "auto" | "ip" = "auto"): string =>
  by === "auto" && req.user?.id ? `u:${req.user.id}` : `ip:${clientIp(req)}`;

/** Tiny fixed-window limiter, in memory. Keyed by user id when signed in, else by IP. */
export function rateLimit(max: number, windowMs = 60_000, by: "auto" | "ip" = "auto") {
  const hits = new Map<string, { count: number; resetAt: number }>();
  setInterval(() => {
    const now = Date.now();
    for (const [key, v] of hits) if (v.resetAt <= now) hits.delete(key);
  }, windowMs).unref();
  return (req: Request, _res: Response, next: NextFunction) => {
    const now = Date.now();
    const key = limitKey(req, by);
    const entry = hits.get(key);
    if (!entry || entry.resetAt <= now) {
      hits.set(key, { count: 1, resetAt: now + windowMs });
      return next();
    }
    if (++entry.count > max) return next(new AppError(429, "rate_limited", "Too many requests, slow down.", true));
    next();
  };
}

/**
 * Throttles failed authentication per IP. Mount it before the auth middleware:
 * once an IP has produced [max] 401s inside the window its requests are refused
 * with 429 (before any token comparison), which stops API_TOKEN / JWT guessing.
 */
export function failedAuthGuard(max = 30, windowMs = 15 * 60_000) {
  const fails = new Map<string, { count: number; resetAt: number }>();
  setInterval(() => {
    const now = Date.now();
    for (const [key, v] of fails) if (v.resetAt <= now) fails.delete(key);
  }, windowMs).unref();
  return (req: Request, res: Response, next: NextFunction) => {
    const ip = clientIp(req);
    const now = Date.now();
    const cur = fails.get(ip);
    if (cur && cur.resetAt > now && cur.count >= max) {
      return next(new AppError(429, "rate_limited", "Too many failed sign-in attempts. Try again later.", true));
    }
    res.on("finish", () => {
      if (res.statusCode !== 401) return;
      const t = Date.now();
      const e = fails.get(ip);
      if (!e || e.resetAt <= t) fails.set(ip, { count: 1, resetAt: t + windowMs });
      else e.count++;
    });
    next();
  };
}
