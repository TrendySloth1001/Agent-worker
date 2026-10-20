import "server-only";
import { jsonError } from "./http";

const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

export function isSameOrigin(headers: Headers, appOrigin?: string): boolean {
  const fetchSite = headers.get("sec-fetch-site");
  if (fetchSite) return fetchSite === "same-origin";
  const origin = headers.get("origin");
  if (!origin) return false;
  if (appOrigin && origin === appOrigin) return true;
  const host = headers.get("x-forwarded-host") ?? headers.get("host");
  try {
    return host !== null && new URL(origin).host === host;
  } catch {
    return false;
  }
}

export function csrfGuard(req: Request, appOrigin?: string): Response | null {
  if (SAFE_METHODS.has(req.method)) return null;
  if (isSameOrigin(req.headers, appOrigin)) return null;
  return jsonError(403, "forbidden_origin", "This request was blocked.");
}
