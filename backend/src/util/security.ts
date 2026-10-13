import type { CorsOptions } from "cors";
import type { NextFunction, Request, Response } from "express";

/**
 * Transport hardening for the API. Production traffic arrives over HTTPS through Cloudflare and the reverse proxy
 * (`trust proxy` is 1), so these only add what the edge does not guarantee: HSTS, strict response headers,
 * a plain-HTTP guard and a CORS policy that never trusts plain-HTTP origins. No certificate pinning: Cloudflare
 * rotates its certificates, so a pin would break the app without notice (a later option: pin the SPKI of the
 * Cloudflare origin CA / use a backup pin).
 */

const HSTS = "max-age=31536000; includeSubDomains";
/** For JSON/binary responses: nothing to load, never framed. HTML pages (home, policies, OAuth pages) keep their own policy. */
const API_CSP = "default-src 'none'; frame-ancestors 'none'; base-uri 'none'";

type Flags = { production: boolean };

export function securityHeaders({ production }: Flags) {
  return (_req: Request, res: Response, next: NextFunction): void => {
    if (production) res.setHeader("Strict-Transport-Security", HSTS);
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("X-Frame-Options", "DENY");
    res.setHeader("Referrer-Policy", "no-referrer");
    res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=(), usb=()");
    res.setHeader("Cross-Origin-Resource-Policy", "same-site");
    // Last-moment defaults, once the handler has chosen the content type: a CSP for non-HTML bodies and no shared caching.
    const writeHead = res.writeHead;
    res.writeHead = function patched(this: Response, ...args: unknown[]) {
      const type = String(res.getHeader("Content-Type") ?? "");
      if (!res.getHeader("Content-Security-Policy") && !type.includes("text/html")) res.setHeader("Content-Security-Policy", API_CSP);
      if (!res.getHeader("Cache-Control")) res.setHeader("Cache-Control", "no-store");
      return (writeHead as (...a: unknown[]) => Response).apply(this, args);
    } as typeof res.writeHead;
    next();
  };
}

/** Behind the proxy, a request the proxy says arrived over plain HTTP is never served in production (health checks carry no such header). */
export function httpsOnly({ production }: Flags) {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!production || req.path === "/health" || req.headers["x-forwarded-proto"] !== "http") return next();
    if (req.method === "GET" || req.method === "HEAD") {
      res.redirect(308, `https://${req.headers.host ?? ""}${req.originalUrl}`);
      return;
    }
    res.status(426).json({ error: { code: "https_required", message: "Use https." } });
  };
}

const LOCAL_HTTP = /^http:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/i;

/** Native apps send no Origin and are always allowed; browsers only from https origins (plain http only for localhost outside production). */
export function corsOptions({ production }: Flags): CorsOptions {
  return {
    origin(origin, cb) {
      if (!origin) return cb(null, true);
      if (origin.startsWith("https://")) return cb(null, true);
      return cb(null, !production && LOCAL_HTTP.test(origin));
    },
  };
}
