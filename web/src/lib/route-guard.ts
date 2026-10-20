import { DEFAULT_NEXT, safeNext } from "./safe-next";

export const LOGIN_PATH = "/login";
export const SESSION_PATH = "/api/auth/session";

const PUBLIC_PATHS = ["/", "/ui"];

export type GuardDecision = { action: "next" } | { action: "redirect"; location: string };

const isPublic = (pathname: string): boolean =>
  PUBLIC_PATHS.some((p) => pathname === p || (p !== "/" && pathname.startsWith(`${p}/`)));

export function guardRoute(pathname: string, search: string, signedIn: boolean): GuardDecision {
  if (pathname === LOGIN_PATH) {
    if (!signedIn) return { action: "next" };
    const next = safeNext(new URLSearchParams(search).get("next"), DEFAULT_NEXT);
    return { action: "redirect", location: next };
  }
  if (signedIn || isPublic(pathname)) return { action: "next" };
  const target = new URLSearchParams({ next: `${pathname}${search}` });
  return { action: "redirect", location: `${SESSION_PATH}?${target.toString()}` };
}
