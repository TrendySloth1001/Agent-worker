import { config } from "../config.js";
import { currentUser } from "../auth/context.js";
import { dropRevokedGithub, githubAuthFor } from "../connections/store.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { recordUsage } from "../db/usage.js";

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
  const t0 = Date.now();
  try {
    res = await fetch(`${API}${path}`, { headers: headers(accept, auth.token), signal: AbortSignal.any(signals) });
  } catch (e) {
    if (opts.signal?.aborted) throw e;
    recordUsage({ provider: "github", model: "rest", kind: "github", ok: false, latencyMs: Date.now() - t0, errorCode: "timeout", errorMessage: "GitHub did not answer in time" });
    throw new AppError(504, "upstream_timeout", "GitHub took too long to answer — try again.", true);
  }
  recordUsage({ provider: "github", model: "rest", kind: "github", ok: res.ok || (res.status === 404 && !!opts.allow404), status: res.status, latencyMs: Date.now() - t0, errorMessage: res.ok ? undefined : `GET ${path.split("?")[0].slice(0, 80)}` });
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
  if (status === 404) return new AppError(404, "not_found", "Couldn't find that on GitHub — it may be private.");
  if (status === 401) return new AppError(502, "upstream_failed", "GitHub didn't accept sparky's access — reconnect GitHub and try again.");
  if ((status === 403 || status === 429) && (rate?.remaining === 0 || /rate limit/i.test(message))) {
    log.info("github rate limit", { resetsAt: rate?.resetsAt ?? null });
    return new AppError(429, "rate_limited", "GitHub needs a short break — try again in a few minutes.", true);
  }
  if (status === 403 || status === 422) log.info("github refused", { status, message: message.slice(0, 160) });
  if (status === 403) return new AppError(403, "forbidden", "GitHub didn't allow that.");
  if (status === 409) return new AppError(404, "not_found", "This repository is empty.");
  if (status === 422) return new AppError(400, "bad_request", "GitHub couldn't do that — check the details and try again.");
  log.warn("github upstream error", { status, message: message.slice(0, 120) });
  return new AppError(502, "upstream_failed", "GitHub isn't responding right now — try again shortly.", true);
}

/**
 * May the current caller change things on GitHub? Only with their own
 * connected account, or the owner on the server token: never with the
 * server token on someone else's behalf (that would act as the owner).
 */
export function canWriteWith(auth: GhAuth): boolean {
  return !!auth.token && (auth.kind === "user" || (auth.kind === "server" && !auth.publicOnly));
}

/** A classic token without the scope to write to this repository (fine-grained tokens report no scopes). */
export function missingWriteScope(scopes: string[] | null, isPrivate: boolean): boolean {
  if (scopes == null) return false;
  if (scopes.includes("repo")) return false;
  return isPrivate || !scopes.includes("public_repo");
}

/** Drops cached GETs of one repository for one token (after a write). */
export function forgetRepo(authKey: string, owner: string, repo: string) {
  const needle = `|/repos/${owner}/${repo}`.toLowerCase();
  for (const k of [...cache.keys()]) if (k.startsWith(`${authKey}|`) && k.toLowerCase().includes(needle)) cache.delete(k);
}

/**
 * A write (POST / PATCH / PUT / DELETE) to the GitHub REST API with the
 * caller's token. Never cached; the repository's cached reads are dropped.
 * Failures map to typed errors the app shows inline: `github_no_permission`
 * (403, or 404 on a write), `github_scope_missing` (the token lacks the repo
 * scope: reconnect), `github_invalid` (422), `github_not_mergeable` (405/409)
 * and `rate_limited`.
 */
export async function ghSend<T = any>(
  method: "POST" | "PATCH" | "PUT" | "DELETE",
  path: string,
  body?: unknown,
  opts: { signal?: AbortSignal } = {},
): Promise<T> {
  const auth = await ghAuth();
  if (!canWriteWith(auth)) throw new AppError(409, "github_not_connected", "Connect your GitHub account to make changes");
  const signals = [AbortSignal.timeout(TIMEOUT_MS), ...(opts.signal ? [opts.signal] : [])];
  let res: Response;
  const t0 = Date.now();
  try {
    res = await fetch(`${API}${path}`, {
      method,
      headers: { ...headers("application/vnd.github+json", auth.token), ...(body === undefined ? {} : { "Content-Type": "application/json" }) },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.any(signals),
    });
  } catch (e) {
    if (opts.signal?.aborted) throw e;
    recordUsage({ provider: "github", model: "rest", kind: "github", ok: false, latencyMs: Date.now() - t0, errorCode: "timeout", errorMessage: "GitHub did not answer in time" });
    throw new AppError(504, "upstream_timeout", "GitHub took too long to answer — try again.", true);
  }
  recordUsage({ provider: "github", model: "rest", kind: "github", ok: res.ok, status: res.status, latencyMs: Date.now() - t0, errorMessage: res.ok ? undefined : `${method} ${path.split("?")[0].slice(0, 80)}` });
  const rate = readRate(res, auth.key);
  const scopeHeader = res.headers.get("x-oauth-scopes");
  const scopes = scopeHeader == null ? null : scopeHeader.split(",").map((x) => x.trim()).filter(Boolean);
  if (scopes) scopesByKey.set(auth.key, scopes);
  const m = path.match(/^\/repos\/([^/]+)\/([^/]+)/);
  if (m) forgetRepo(auth.key, m[1], m[2]);
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
    throw mapWriteError(res.status, message, rate, scopes, res.headers.get("x-accepted-oauth-scopes"));
  }
  if (res.status === 204) return null as T;
  const text = await res.text();
  return (text ? JSON.parse(text) : null) as T;
}

/** GitHub's answer to a write, as an error the app can explain. */
export function mapWriteError(status: number, message: string, rate: RateInfo | null, scopes: string[] | null = null, accepted: string | null = null): AppError {
  if ((status === 403 || status === 429) && (rate?.remaining === 0 || /rate limit/i.test(message))) return mapError(status, message, rate);
  if (status === 403 || status === 404) {
    const need = (accepted ?? "").split(",").map((x) => x.trim()).filter(Boolean);
    const lacksScope = scopes != null && need.length > 0 && !need.some((s) => scopes.includes(s));
    if (lacksScope || /scope|not accessible by (integration|personal access token)/i.test(message)) {
      return new AppError(403, "github_scope_missing", "sparky doesn't have permission to do this on GitHub yet. Reconnect GitHub and allow repository access.");
    }
    log.info("github write refused", { status, message: message.slice(0, 160) });
    return new AppError(403, "github_no_permission", "You don't have access to change this on GitHub.");
  }
  if (status === 405 || status === 409 || status === 422) log.info("github write rejected", { status, message: message.slice(0, 160) });
  if (status === 405 || status === 409) return new AppError(409, "github_not_mergeable", "This pull request can't be merged right now.");
  if (status === 410) return new AppError(409, "github_invalid", "That's turned off for this repository.");
  if (status === 422) return new AppError(422, "github_invalid", "GitHub couldn't make that change — check the details and try again.");
  return mapError(status, message, rate);
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
  if (!auth.token) throw new AppError(503, "github_disabled", "Connect GitHub to see this.");
  const signals = [AbortSignal.timeout(TIMEOUT_MS * 2), ...(opts.signal ? [opts.signal] : [])];
  let res: Response;
  const t0 = Date.now();
  try {
    res = await fetch(`${API}/graphql`, {
      method: "POST",
      headers: { ...headers("application/json", auth.token), "Content-Type": "application/json" },
      body: JSON.stringify({ query, variables }),
      signal: AbortSignal.any(signals),
    });
  } catch (e) {
    if (opts.signal?.aborted) throw e;
    recordUsage({ provider: "github", model: "graphql", kind: "github", ok: false, latencyMs: Date.now() - t0, errorCode: "timeout", errorMessage: "GitHub did not answer in time" });
    throw new AppError(504, "upstream_timeout", "GitHub took too long to answer — try again.", true);
  }
  recordUsage({ provider: "github", model: "graphql", kind: "github", ok: res.ok, status: res.status, latencyMs: Date.now() - t0 });
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
  if (errors.some((e) => e.type === "FORBIDDEN")) throw mapWriteError(403, String(errors[0]?.message ?? ""), rate);
  // Partial: a missing alias (deleted branch) is fine; the caller checks for a null repository.
  if (errors.length && opts.partial && body.data) return body.data as T;
  if (errors.some((e) => e.type === "NOT_FOUND")) throw new AppError(404, "not_found", "Couldn't find that on GitHub — it may be private.");
  if (errors.length) {
    log.warn("github graphql error", { message: String(errors[0]?.message ?? "").slice(0, 120) });
    throw new AppError(502, "upstream_failed", "GitHub isn't responding right now — try again shortly.", true);
  }
  return body.data as T;
}
