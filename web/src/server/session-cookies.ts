import "server-only";
import {
  ACCESS_COOKIE,
  REFRESH_COOKIE,
  REFRESH_COOKIE_PATH,
  WEB_FLOW_COOKIE,
  WEB_FLOW_COOKIE_PATH,
} from "./cookie-names";

const SKEW_SECONDS = 30;
export const WEB_FLOW_MAX_AGE = 10 * 60;

export interface CookieOptions {
  httpOnly: true;
  secure: boolean;
  sameSite: "lax";
  path: string;
  maxAge: number;
}

export interface CookieSpec {
  name: string;
  value: string;
  options: CookieOptions;
}

export interface SessionTokens {
  accessToken: string;
  accessExpiresAt: string;
  refreshToken: string;
  refreshExpiresAt: string;
}

const secondsUntil = (iso: string, now: number): number => {
  const ms = Date.parse(iso) - now;
  return Number.isFinite(ms) ? Math.floor(ms / 1000) : 0;
};

const spec = (
  name: string,
  value: string,
  path: string,
  maxAge: number,
  secure: boolean,
): CookieSpec => ({
  name,
  value,
  options: { httpOnly: true, secure, sameSite: "lax", path, maxAge: Math.max(0, maxAge) },
});

export function sessionCookies(
  tokens: SessionTokens,
  secure: boolean,
  now: number = Date.now(),
): CookieSpec[] {
  return [
    spec(
      ACCESS_COOKIE,
      tokens.accessToken,
      "/",
      secondsUntil(tokens.accessExpiresAt, now) - SKEW_SECONDS,
      secure,
    ),
    spec(
      REFRESH_COOKIE,
      tokens.refreshToken,
      REFRESH_COOKIE_PATH,
      secondsUntil(tokens.refreshExpiresAt, now),
      secure,
    ),
  ];
}

export function clearedSessionCookies(secure: boolean): CookieSpec[] {
  return [
    spec(ACCESS_COOKIE, "", "/", 0, secure),
    spec(REFRESH_COOKIE, "", REFRESH_COOKIE_PATH, 0, secure),
  ];
}

export const webFlowCookie = (value: string, secure: boolean): CookieSpec =>
  spec(WEB_FLOW_COOKIE, value, WEB_FLOW_COOKIE_PATH, WEB_FLOW_MAX_AGE, secure);

export const clearedWebFlowCookie = (secure: boolean): CookieSpec =>
  spec(WEB_FLOW_COOKIE, "", WEB_FLOW_COOKIE_PATH, 0, secure);
