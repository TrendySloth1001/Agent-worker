import "server-only";
import { cookies } from "next/headers";
import { ACCESS_COOKIE, REFRESH_COOKIE } from "./cookie-names";
import { env } from "./env";
import {
  clearedSessionCookies,
  sessionCookies,
  type CookieSpec,
  type SessionTokens,
} from "./session-cookies";

export interface StoredTokens {
  accessToken: string | null;
  refreshToken: string | null;
}

export interface SessionStore {
  read(): StoredTokens;
  write(tokens: SessionTokens): void;
  clear(): void;
}

export async function cookieSessionStore(
  options: { readOnly?: boolean } = {},
): Promise<SessionStore> {
  const jar = await cookies();
  const apply = (specs: CookieSpec[]) => {
    if (options.readOnly) return;
    for (const { name, value, options: cookieOptions } of specs)
      jar.set(name, value, cookieOptions);
  };
  return {
    read: () => ({
      accessToken: jar.get(ACCESS_COOKIE)?.value ?? null,
      refreshToken: jar.get(REFRESH_COOKIE)?.value ?? null,
    }),
    write: (tokens) => apply(sessionCookies(tokens, env.cookieSecure)),
    clear: () => apply(clearedSessionCookies(env.cookieSecure)),
  };
}
