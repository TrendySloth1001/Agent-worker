import { config } from "../config.js";
import { currentUser } from "../auth/context.js";
import { dropRevokedGithub, githubAuthFor } from "../connections/store.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";

const API = "https://api.github.com";
const TTL_MS = 5 * 60_000;
const CACHE_MAX = 400;
const TIMEOUT_MS = 12_000;

export type RateInfo = { limit: number | null; remaining: number | null; resetsAt: string | null; resource: string | null };

/**
 * Whose token a GitHub call uses. A user who connected GitHub always uses
 * their own token (their private repos, their identity). Otherwise the
 * server's token (GITHUB_TOKEN, the owner's): in full for the owner, and for
 * everyone else only for public data (`publicOnly`: private results are
 * hidden by githubGate and the services).
 */
export type GhAuth = {
  kind: "user" | "server" | "none";
  token: string | null;
  /** Partitions caches, quotas and scopes per token. */
  key: string;
  publicOnly: boolean;
  /** The connected account's login (kind "user"). */
  login: string | null;
  userId: string | null;
};

export async function ghAuth(): Promise<GhAuth> {
  const u = currentUser();
  if (u?.id) {
    const conn = await githubAuthFor(u.id).catch((e) => {
      log.warn("github connection lookup failed", { message: (e as Error).message.slice(0, 80) });
      return null;
    });
    if (conn) return { kind: "user", token: conn.token, key: `u:${u.id}`, publicOnly: false, login: conn.login, userId: u.id };
  }
  const owner = !u || u.role === "owner";
  if (config.githubToken) return { kind: "server", token: config.githubToken, key: owner ? "srv" : "srv-public", publicOnly: !owner, login: null, userId: u?.id ?? null };
  return { kind: "none", token: null, key: "anon", publicOnly: true, login: null, userId: u?.id ?? null };
}

/** True when the caller may see private GitHub data (connected, or the owner on the server token). */
export async function canSeePrivate(): Promise<boolean> {
  return !(await ghAuth()).publicOnly;
}

/** The latest rate-limit headers GitHub sent, per token and resource (core, search, …). */
const rates = new Map<string, RateInfo>();
export async function lastRate(resource = "core"): Promise<RateInfo | null> {
  return rates.get(`${(await ghAuth()).key}|${resource}`) ?? null;
}

/** OAuth scopes of the current token, from the last X-OAuth-Scopes header (classic PATs and OAuth tokens). */
const scopesByKey = new Map<string, string[]>();
export async function tokenScopes(): Promise<string[] | null> {
  return scopesByKey.get((await ghAuth()).key) ?? null;
}

const cache = new Map<string, { at: number; value: unknown }>();

function remember(key: string, value: unknown) {
  cache.delete(key);
  cache.set(key, { at: Date.now(), value });
  while (cache.size > CACHE_MAX) cache.delete(cache.keys().next().value!);
}

function headers(accept: string, token: string | null): Record<string, string> {
  return {
    Accept: accept,
    "User-Agent": "AgentWorker",
    "X-GitHub-Api-Version": "2022-11-28",
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
  };
}

function readRate(res: Response, authKey: string): RateInfo | null {
  const num = (h: string) => {
    const v = res.headers.get(h);
    return v == null ? null : Number(v);
  };
  const remaining = num("x-ratelimit-remaining");
  if (remaining == null) return null;
  const reset = num("x-ratelimit-reset");
  const info: RateInfo = {
    limit: num("x-ratelimit-limit"),
    remaining,
    resetsAt: reset ? new Date(reset * 1000).toISOString() : null,
    resource: res.headers.get("x-ratelimit-resource"),
  };
  rates.set(`${authKey}|${info.resource ?? "core"}`, info);
  return info;
}

export type GhOptions = {
  accept?: string;
  /** Return the body as text instead of JSON. */
  text?: boolean;
  ttlMs?: number;
  signal?: AbortSignal;
  /** Resolve 404 to null instead of throwing. */
  allow404?: boolean;
};

/**
 * GET a GitHub REST path (e.g. `/repos/vercel/next.js`). Successful responses
 * are cached in memory for a few minutes; failures map to AppError.
 */
export async function gh<T = any>(path: string, opts: GhOptions = {}): Promise<T> {
  const accept = opts.accept ?? "application/vnd.github+json";
  const auth = await ghAuth();
  // Per token: users never see each other's (private) responses.
  const key = `${auth.key}|${accept}|${opts.text ? "t" : "j"}|${path}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < (opts.ttlMs ?? TTL_MS)) return hit.value as T;

  const signals = [AbortSignal.timeout(TIMEOUT_MS), ...(opts.signal ? [opts.signal] : [])];
  let res: Response;
  try {
    res = await fetch(`${API}${path}`, { headers: headers(accept, auth.token), signal: AbortSignal.any(signals) });
  } catch (e) {
    if (opts.signal?.aborted) throw e;
    throw new AppError(504, "upstream_timeout", "GitHub did not answer in time", true);
  }
  const rate = readRate(res, auth.key);
  const scopeHeader = res.headers.get("x-oauth-scopes");
  if (scopeHeader != null) scopesByKey.set(auth.key, scopeHeader.split(",").map((x) => x.trim()).filter(Boolean));
  if (!res.ok) {
    if (res.status === 401 && auth.kind === "user" && auth.userId) {
      // The user revoked the app on GitHub: forget the dead token.
      await dropRevokedGithub(auth.userId);
      throw new AppError(409, "github_not_connected", "GitHub access was revoked. Connect GitHub again.");
    }
    if (res.status === 404 && opts.allow404) return null as T;
    let message = "";
    try {
      message = ((await res.json()) as { message?: string })?.message ?? "";
    } catch {
      /* not JSON */
    }
    throw mapError(res.status, message, rate);
  }
  const value = res.status === 204 ? null : opts.text ? await res.text() : await res.json();
  remember(key, value);
  return value as T;
}

function mapError(status: number, message: string, rate: RateInfo | null): AppError {
  if (status === 404) return new AppError(404, "not_found", "GitHub: not found (or private)");
  if (status === 401) return new AppError(502, "upstream_failed", "GitHub rejected the token");
  if ((status === 403 || status === 429) && (rate?.remaining === 0 || /rate limit/i.test(message))) {
    const when = rate?.resetsAt ? ` until ${rate.resetsAt.slice(11, 16)} UTC` : "";
    return new AppError(429, "rate_limited", `GitHub rate limit reached${when}`, true);
  }
  if (status === 403) return new AppError(403, "forbidden", `GitHub: ${message || "forbidden"}`.slice(0, 160));
  if (status === 409) return new AppError(404, "not_found", "GitHub: the repository is empty");
  if (status === 422) return new AppError(400, "bad_request", `GitHub: ${message || "invalid request"}`.slice(0, 160));
  log.warn("github upstream error", { status, message: message.slice(0, 120) });
  return new AppError(502, "upstream_failed", `GitHub error ${status}`, true);
}

/** The server token is set (public GitHub features for everyone). */
export const githubEnabled = () => !!config.githubToken;

export type GqlOptions = {
  signal?: AbortSignal;
  /** Return the data despite field errors (e.g. one failed alias); NOT_FOUND / rate limits still throw. */
  partial?: boolean;
};

/**
 * POST a GitHub GraphQL query with the same token as gh() (GraphQL always
 * needs one). Not cached here: callers cache the shaped result. A missing
 * repository maps to 404; other GraphQL errors to 502.
 */
export async function ghGraphql<T = any>(query: string, variables: Record<string, unknown>, opts: GqlOptions = {}): Promise<T> {
  const auth = await ghAuth();
  if (!auth.token) throw new AppError(503, "github_disabled", "GitHub GraphQL needs a token");
  const signals = [AbortSignal.timeout(TIMEOUT_MS * 2), ...(opts.signal ? [opts.signal] : [])];
  let res: Response;
  try {
    res = await fetch(`${API}/graphql`, {
      method: "POST",
      headers: { ...headers("application/json", auth.token), "Content-Type": "application/json" },
      body: JSON.stringify({ query, variables }),
      signal: AbortSignal.any(signals),
    });
  } catch (e) {
    if (opts.signal?.aborted) throw e;
    throw new AppError(504, "upstream_timeout", "GitHub did not answer in time", true);
  }
  const rate = readRate(res, auth.key);
  if (!res.ok) {
    if (res.status === 401 && auth.kind === "user" && auth.userId) {
      await dropRevokedGithub(auth.userId);
      throw new AppError(409, "github_not_connected", "GitHub access was revoked. Connect GitHub again.");
    }
    let message = "";
    try {
      message = ((await res.json()) as { message?: string })?.message ?? "";
    } catch {
      /* not JSON */
    }
    throw mapError(res.status, message, rate);
  }
  const body = (await res.json()) as { data?: T; errors?: { type?: string; message?: string }[] };
  const errors = body.errors ?? [];
  if (errors.some((e) => e.type === "RATE_LIMITED")) throw mapError(403, "rate limit", rate);
  // Partial: a missing alias (deleted branch) is fine; the caller checks for a null repository.
  if (errors.length && opts.partial && body.data) return body.data as T;
  if (errors.some((e) => e.type === "NOT_FOUND")) throw new AppError(404, "not_found", "GitHub: not found (or private)");
  if (errors.length) {
    log.warn("github graphql error", { message: String(errors[0]?.message ?? "").slice(0, 120) });
    throw new AppError(502, "upstream_failed", "GitHub GraphQL error", true);
  }
  return body.data as T;
}
