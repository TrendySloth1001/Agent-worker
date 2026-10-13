import type { NextFunction, Request, Response } from "express";
import { AppError } from "./errors.js";
import { USER_MSG } from "./userMessages.js";
import { noteUserCap } from "../llm/budget.js";

/**
 * The caller's IP, never empty. Production sits behind a Cloudflare tunnel and
 * Traefik with no host port, so Cloudflare's `CF-Connecting-IP` is the real
 * client; otherwise `req.ip` (honours `trust proxy`).
 */
export const clientIp = (req: Request): string => {
  const cf = req.headers?.["cf-connecting-ip"];
  if (typeof cf === "string" && cf.trim()) return cf.trim();
  return req.ip ?? req.socket?.remoteAddress ?? "unknown";
};

/**
 * Bucket key. Authenticated routes count per user (so users behind one NAT or
 * proxy don't share a budget); anything without a user (auth routes) counts per IP.
 */
export const limitKey = (req: Request, by: "auto" | "ip" = "auto"): string =>
  by === "auto" && req.user?.id ? `u:${req.user.id}` : `ip:${clientIp(req)}`;

/** The friendly 429 every per-user cap answers with. */
export const slowDown = () => new AppError(429, "rate_limited", USER_MSG.slowDown, true);

/**
 * Tiny fixed-window limiter, in memory. Keyed by user id when signed in, else by IP.
 * [opts.when] limits only matching requests (e.g. Round Table runs); [opts.name] labels telemetry.
 */
export function rateLimit(max: number, windowMs = 60_000, by: "auto" | "ip" = "auto", opts: { when?: (req: Request) => boolean; name?: string } = {}) {
  const hits = new Map<string, { count: number; resetAt: number }>();
  setInterval(() => {
    const now = Date.now();
    for (const [key, v] of hits) if (v.resetAt <= now) hits.delete(key);
  }, windowMs).unref();
  return (req: Request, res: Response, next: NextFunction) => {
    if (opts.when && !opts.when(req)) return next();
    const now = Date.now();
    const key = limitKey(req, by);
    const entry = hits.get(key);
    if (!entry || entry.resetAt <= now) {
      hits.set(key, { count: 1, resetAt: now + windowMs });
      return next();
    }
    if (++entry.count > max) {
      noteUserCap(opts.name ?? req.path);
      res.setHeader?.("Retry-After", String(Math.max(1, Math.ceil((entry.resetAt - now) / 1000))));
      return next(slowDown());
    }
    next();
  };
}

/**
 * Caps the requests one user (or IP) has in flight at once. Over the cap, a
 * request waits up to [queueMs] for one of its own to finish (a short burst is
 * served, not refused); after that it gets the friendly 429.
 */
export function inFlightLimit(max: number, queueMs = 4_000, name = "") {
  const active = new Map<string, number>();
  const waiters = new Map<string, Array<() => void>>();
  const release = (key: string) => {
    const queue = waiters.get(key);
    const next = queue?.shift();
    if (queue && queue.length === 0) waiters.delete(key);
    // The slot passes straight to the next waiter; otherwise it frees up.
    if (next) return next();
    const n = (active.get(key) ?? 1) - 1;
    if (n <= 0) active.delete(key);
    else active.set(key, n);
  };
  const take = (key: string, timeoutMs: number): Promise<boolean> => {
    if ((active.get(key) ?? 0) < max) {
      active.set(key, (active.get(key) ?? 0) + 1);
      return Promise.resolve(true);
    }
    if (timeoutMs <= 0) return Promise.resolve(false);
    return new Promise((resolve) => {
      const grant = () => {
        clearTimeout(timer);
        resolve(true);
      };
      const timer = setTimeout(() => {
        const q = waiters.get(key);
        if (q) {
          const i = q.indexOf(grant);
          if (i >= 0) q.splice(i, 1);
          if (q.length === 0) waiters.delete(key);
        }
        resolve(false);
      }, timeoutMs);
      const q = waiters.get(key) ?? [];
      q.push(grant);
      waiters.set(key, q);
    });
  };
  const middleware = async (req: Request, res: Response, next: NextFunction) => {
    const key = limitKey(req);
    if (!(await take(key, queueMs))) {
      noteUserCap(name || req.path);
      res.setHeader?.("Retry-After", String(Math.max(1, Math.ceil(queueMs / 1000))));
      return next(slowDown());
    }
    let done = false;
    const free = () => {
      if (done) return;
      done = true;
      release(key);
    };
    res.on("finish", free);
    res.on("close", free);
    next();
  };
  /** Test hook: requests in flight for [key]. */
  middleware.inFlight = (key: string) => active.get(key) ?? 0;
  return middleware;
}

/** Several limiters as one middleware (run in order; the first refusal wins). */
export function limits(...mws: Array<(req: Request, res: Response, next: NextFunction) => unknown>) {
  return (req: Request, res: Response, next: NextFunction) => {
    let i = 0;
    const step = (err?: unknown) => {
      if (err || i >= mws.length) return next(err as Error | undefined);
      void mws[i++](req, res, step);
    };
    step();
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
