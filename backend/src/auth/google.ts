import { OAuth2Client, type TokenPayload } from "google-auth-library";
import { config } from "../config.js";
import { AppError } from "../util/errors.js";
import type { SsoProfile } from "./sso.js";

/**
 * "Continue with Google" (native, no redirect): the app gets an ID token from
 * Google Sign-In / Credential Manager with serverClientId = our Web client id,
 * and the server verifies it here. google-auth-library checks the signature
 * (Google's rotating certs, cached), `aud` and `exp`; the claims are checked
 * again below so a swapped-in verifier (tests) gets the same rules.
 */

const ISSUERS = new Set(["accounts.google.com", "https://accounts.google.com"]);
/** Allowed clock skew for `exp`, seconds. */
const SKEW_S = 300;

export type GoogleVerifier = (idToken: string, audience: string) => Promise<TokenPayload | undefined>;

let client: OAuth2Client | null = null;
export const googleVerify: GoogleVerifier = async (idToken, audience) => {
  client ??= new OAuth2Client();
  const ticket = await client.verifyIdToken({ idToken, audience });
  return ticket.getPayload();
};

export const googleNotConfigured = () =>
  new AppError(503, "google_not_configured", "Google sign-in isn't available right now.");

const invalid = () => new AppError(401, "invalid_google_token", "Google sign-in failed. Try again.");

/** Verifies [idToken] and returns who Google says it is. */
export async function verifyGoogleIdToken(
  idToken: string,
  opts: { clientId?: string; verify?: GoogleVerifier; now?: () => number } = {},
): Promise<SsoProfile> {
  const audience = "clientId" in opts ? opts.clientId : config.google.webClientId;
  if (!audience) throw googleNotConfigured();
  const verify = opts.verify ?? googleVerify;
  let payload: TokenPayload | undefined;
  try {
    payload = await verify(idToken, audience);
  } catch {
    throw invalid();
  }
  if (!payload) throw invalid();
  const nowS = Math.floor((opts.now ?? Date.now)() / 1000);
  const aud = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!aud.includes(audience)) throw invalid();
  if (!payload.iss || !ISSUERS.has(payload.iss)) throw invalid();
  if (typeof payload.exp !== "number" || payload.exp + SKEW_S < nowS) throw invalid();
  if (!payload.sub) throw invalid();
  const email = typeof payload.email === "string" && payload.email.includes("@") ? payload.email : null;
  return {
    provider: "google",
    providerUserId: String(payload.sub),
    email,
    // Google sends a boolean, older tokens the string "true".
    emailVerified: !!email && (payload.email_verified === true || (payload.email_verified as unknown) === "true"),
    name: typeof payload.name === "string" ? payload.name : null,
    avatarUrl: typeof payload.picture === "string" ? payload.picture : null,
    login: null,
  };
}
