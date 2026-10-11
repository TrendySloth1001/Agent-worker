import type { NextFunction, Request, Response } from "express";
import { AppError } from "./errors.js";

/** Tiny per-IP fixed-window limiter, in memory. */
export function rateLimit(max: number, windowMs = 60_000) {
  const hits = new Map<string, { count: number; resetAt: number }>();
  setInterval(() => {
    const now = Date.now();
    for (const [key, v] of hits) if (v.resetAt <= now) hits.delete(key);
  }, windowMs).unref();
  return (req: Request, _res: Response, next: NextFunction) => {
    const now = Date.now();
    const key = req.ip ?? "unknown";
    const entry = hits.get(key);
    if (!entry || entry.resetAt <= now) {
      hits.set(key, { count: 1, resetAt: now + windowMs });
      return next();
    }
    if (++entry.count > max) return next(new AppError(429, "rate_limited", "Too many requests, slow down.", true));
    next();
  };
}
