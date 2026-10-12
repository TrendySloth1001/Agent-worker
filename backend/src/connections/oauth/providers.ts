import { config } from "../../config.js";

/**
 * The OAuth connectors sparky can link besides GitHub (which keeps its own
 * device + web flows). One entry per provider: where to send the user, how to
 * swap the code, which scopes, how to refresh and revoke, and who the account
 * is. Adding a connector is one entry here plus its API client.
 */

export type ProviderId = "google_drive" | "notion";
export const PROVIDER_IDS: readonly ProviderId[] = ["google_drive", "notion"];
export const isProviderId = (v: unknown): v is ProviderId => typeof v === "string" && (PROVIDER_IDS as readonly string[]).includes(v);

/** The token endpoint's answer, normalized. Never logged. */
export type TokenGrant = {
  accessToken: string;
  refreshToken: string | null;
  /** Seconds; 0 when the token does not expire. */
  expiresIn: number;
  scopes: string[];
  /** The raw JSON (Notion puts the workspace and owner here). */
  raw: Record<string, unknown>;
};

/** Who the connection belongs to; stored on the connections row. */
export type AccountProfile = {
  id: string;
  login: string;
  name: string | null;
  email: string | null;
  avatarUrl: string | null;
  /** Non-secret extras (Notion workspace name, icon, id). */
  meta: Record<string, unknown>;
};

export type ProviderDeps = { fetch: typeof fetch };

export type OAuthProvider = {
  id: ProviderId;
  name: string;
  authorizeUrl: string;
  tokenUrl: string;
  /** Space-separated in the authorize URL. */
  scopes: string[];
  /** RFC 7636 S256 supported. */
  pkce: boolean;
  /** How the client authenticates at the token endpoint. */
  tokenAuth: "body" | "basic-json";
  /** Refresh tokens are honoured (and may rotate). */
  refresh: boolean;
  clientId: () => string | undefined;
  clientSecret: () => string | undefined;
  /** Extra authorize parameters; [firstConnect] when the user has no row yet. */
  authorizeParams: (firstConnect: boolean) => Record<string, string>;
  /** Who approved; may call the provider with the fresh token. */
  profile: (grant: TokenGrant, deps: ProviderDeps) => Promise<AccountProfile>;
  /** Revokes [token] at the provider. True when the provider confirmed (or already forgot it). */
  revoke: ((token: string, deps: ProviderDeps) => Promise<boolean>) | null;
  /** Where "Open in …" goes. */
  homeUrl: string;
};

const TIMEOUT_MS = 10_000;
const str = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : null);

export const GOOGLE_DRIVE_SCOPE = "https://www.googleapis.com/auth/drive.file";
export const GOOGLE_USERINFO_URL = "https://openidconnect.googleapis.com/v1/userinfo";
export const GOOGLE_REVOKE_URL = "https://oauth2.googleapis.com/revoke";
export const NOTION_API = "https://api.notion.com/v1";
/** Stable Notion API version used for every call (search, blocks, pages). */
export const NOTION_VERSION = "2022-06-28";

export const googleDrive: OAuthProvider = {
  id: "google_drive",
  name: "Google Drive",
  authorizeUrl: "https://accounts.google.com/o/oauth2/v2/auth",
  tokenUrl: "https://oauth2.googleapis.com/token",
  // drive.file: only files the user picks or sparky creates (not a restricted scope).
  scopes: ["openid", "email", "profile", GOOGLE_DRIVE_SCOPE],
  pkce: true,
  tokenAuth: "body",
  refresh: true,
  clientId: () => config.google.webClientId,
  clientSecret: () => config.google.webClientSecret,
  authorizeParams: (firstConnect) => ({
    access_type: "offline",
    include_granted_scopes: "true",
    // Consent again on a first connect so Google returns a refresh token.
    prompt: firstConnect ? "consent" : "select_account",
  }),
  async profile(grant, deps) {
    const res = await deps.fetch(GOOGLE_USERINFO_URL, {
      headers: { Authorization: `Bearer ${grant.accessToken}` },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    const j = (await res.json().catch(() => ({}))) as Record<string, unknown>;
    if (!res.ok || !str(j.sub)) throw new Error(`google userinfo ${res.status}`);
    const email = str(j.email);
    return {
      id: String(j.sub),
      login: email ?? String(j.sub),
      name: str(j.name),
      email,
      avatarUrl: str(j.picture),
      meta: {},
    };
  },
  async revoke(token, deps) {
    const res = await deps.fetch(GOOGLE_REVOKE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ token }).toString(),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    // 400 invalid_token: already revoked or expired; nothing left to take back.
    return res.ok || res.status === 400;
  },
  homeUrl: "https://drive.google.com/drive/my-drive",
};

const basic = (id: string, secret: string) => `Basic ${Buffer.from(`${id}:${secret}`).toString("base64")}`;

export const notion: OAuthProvider = {
  id: "notion",
  name: "Notion",
  authorizeUrl: `${NOTION_API}/oauth/authorize`,
  tokenUrl: `${NOTION_API}/oauth/token`,
  // Notion has no scopes in the URL: capabilities are set on the integration
  // and the user picks the pages to share on the consent screen.
  scopes: [],
  pkce: false,
  tokenAuth: "basic-json",
  refresh: true,
  clientId: () => config.notion.clientId,
  clientSecret: () => config.notion.clientSecret,
  authorizeParams: () => ({ owner: "user" }),
  async profile(grant) {
    const r = grant.raw;
    const owner = (r.owner ?? {}) as Record<string, unknown>;
    const user = (owner.user ?? {}) as Record<string, unknown>;
    const person = (user.person ?? {}) as Record<string, unknown>;
    const workspaceId = str(r.workspace_id) ?? "";
    const workspaceName = str(r.workspace_name);
    const email = str(person.email);
    const icon = str(r.workspace_icon);
    return {
      id: str(user.id) ?? str(r.bot_id) ?? workspaceId,
      login: email ?? workspaceName ?? "notion",
      name: str(user.name) ?? workspaceName,
      email,
      avatarUrl: str(user.avatar_url) ?? (icon && /^https:\/\//.test(icon) ? icon : null),
      meta: {
        workspaceId,
        workspaceName,
        // Emoji icons are kept as text; image icons are URLs.
        workspaceIcon: icon,
        botId: str(r.bot_id),
      },
    };
  },
  async revoke(token, deps) {
    const id = config.notion.clientId;
    const secret = config.notion.clientSecret;
    if (!id || !secret) return false;
    const res = await deps.fetch(`${NOTION_API}/oauth/revoke`, {
      method: "POST",
      headers: { Authorization: basic(id, secret), "Content-Type": "application/json", "Notion-Version": NOTION_VERSION },
      body: JSON.stringify({ token }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    return res.ok || res.status === 400 || res.status === 401;
  },
  homeUrl: "https://www.notion.so",
};

export const PROVIDERS: Record<ProviderId, OAuthProvider> = { google_drive: googleDrive, notion };

export const providerConfigured = (p: OAuthProvider) => !!p.clientId() && !!p.clientSecret();

/** The token endpoint request for [p] (code exchange or refresh). */
export function tokenRequest(p: OAuthProvider, params: Record<string, string>): RequestInit {
  const id = p.clientId() ?? "";
  const secret = p.clientSecret() ?? "";
  if (p.tokenAuth === "basic-json") {
    return {
      method: "POST",
      headers: { Authorization: basic(id, secret), "Content-Type": "application/json", Accept: "application/json", "Notion-Version": NOTION_VERSION },
      body: JSON.stringify(params),
    };
  }
  return {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" },
    body: new URLSearchParams({ client_id: id, client_secret: secret, ...params }).toString(),
  };
}

/** Normalizes a token endpoint JSON answer; null when it carries no access token. */
export function parseGrant(j: Record<string, unknown>): TokenGrant | null {
  if (typeof j.access_token !== "string" || !j.access_token) return null;
  const expiresIn = Number(j.expires_in);
  return {
    accessToken: j.access_token,
    refreshToken: typeof j.refresh_token === "string" && j.refresh_token ? j.refresh_token : null,
    expiresIn: Number.isFinite(expiresIn) && expiresIn > 0 ? expiresIn : 0,
    scopes: typeof j.scope === "string" ? j.scope.split(/[\s,]+/).filter(Boolean) : [],
    raw: j,
  };
}
