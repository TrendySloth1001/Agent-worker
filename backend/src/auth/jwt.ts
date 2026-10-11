import { createHmac, randomBytes, createHash, timingSafeEqual } from "node:crypto";
import { config } from "../config.js";

export type AccessClaims = { sub: string; role: "owner" | "user"; sid: string; iat: number; exp: number };

const b64 = (b: Buffer | string) => Buffer.from(b).toString("base64url");
const HEADER = b64(JSON.stringify({ alg: "HS256", typ: "JWT" }));

function secret(): string {
  const s = config.auth.jwtSecret;
  if (!s || s.length < 32) throw new Error("AUTH_JWT_SECRET is missing or too short");
  return s;
}

const sign = (data: string) => createHmac("sha256", secret()).update(data).digest("base64url");

/** Short-lived HS256 access token. */
export function signAccess(c: { sub: string; role: "owner" | "user"; sid: string }): { token: string; expiresAt: string } {
  const iat = Math.floor(Date.now() / 1000);
  const exp = iat + config.auth.accessTtlS;
  const body = `${HEADER}.${b64(JSON.stringify({ ...c, iat, exp }))}`;
  return { token: `${body}.${sign(body)}`, expiresAt: new Date(exp * 1000).toISOString() };
}

/** Claims of a valid, unexpired token, or null. */
export function verifyAccess(token: string): AccessClaims | null {
  const parts = token.split(".");
  if (parts.length !== 3 || parts[0] !== HEADER) return null;
  const want = Buffer.from(sign(`${parts[0]}.${parts[1]}`));
  const got = Buffer.from(parts[2]);
  if (want.length !== got.length || !timingSafeEqual(want, got)) return null;
  try {
    const c = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8")) as AccessClaims;
    if (typeof c.sub !== "string" || typeof c.exp !== "number" || c.exp * 1000 <= Date.now()) return null;
    return c;
  } catch {
    return null;
  }
}

/** Opaque refresh token; only its hash is stored. */
export function newRefreshToken(): string {
  return randomBytes(32).toString("base64url");
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}
