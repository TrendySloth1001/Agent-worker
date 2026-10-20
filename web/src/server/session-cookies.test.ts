// @vitest-environment node
import { describe, expect, it } from "vitest";
import { ACCESS_COOKIE, REFRESH_COOKIE } from "./cookie-names";
import { clearedSessionCookies, sessionCookies } from "./session-cookies";

const NOW = Date.parse("2026-01-01T00:00:00Z");
const tokens = {
  accessToken: "access",
  accessExpiresAt: "2026-01-01T00:15:00Z",
  refreshToken: "refresh",
  refreshExpiresAt: "2026-01-31T00:00:00Z",
};

describe("sessionCookies", () => {
  const [access, refresh] = sessionCookies(tokens, true, NOW);

  it("keeps the access cookie just shorter than the token and site-wide", () => {
    expect(access?.name).toBe(ACCESS_COOKIE);
    expect(access?.options).toMatchObject({ path: "/", maxAge: 15 * 60 - 30 });
  });

  it("scopes the refresh cookie to the API paths for the refresh lifetime", () => {
    expect(refresh?.name).toBe(REFRESH_COOKIE);
    expect(refresh?.options).toMatchObject({ path: "/api", maxAge: 30 * 24 * 3600 });
  });

  it("is httpOnly and SameSite=Lax, Secure as configured", () => {
    for (const cookie of [access, refresh]) {
      expect(cookie?.options).toMatchObject({ httpOnly: true, sameSite: "lax", secure: true });
    }
    expect(sessionCookies(tokens, false, NOW)[0]?.options.secure).toBe(false);
  });

  it("never gives a negative lifetime for an expired token", () => {
    const expired = sessionCookies(
      { ...tokens, accessExpiresAt: "2025-12-31T00:00:00Z" },
      true,
      NOW,
    );
    expect(expired[0]?.options.maxAge).toBe(0);
  });
});

describe("clearedSessionCookies", () => {
  it("expires both cookies on their original paths", () => {
    const cleared = clearedSessionCookies(true);
    expect(cleared.map((c) => [c.name, c.value, c.options.path, c.options.maxAge])).toEqual([
      [ACCESS_COOKIE, "", "/", 0],
      [REFRESH_COOKIE, "", "/api", 0],
    ]);
  });
});
