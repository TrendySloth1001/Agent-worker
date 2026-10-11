import { config } from "../config.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";

const API = "https://api.github.com";
const TTL_MS = 5 * 60_000;
const CACHE_MAX = 400;
const TIMEOUT_MS = 12_000;

export type RateInfo = { limit: number | null; remaining: number | null; resetsAt: string | null; resource: string | null };

/** The latest rate-limit headers GitHub sent, per resource (core, search, …). */
const rates = new Map<string, RateInfo>();
export const lastRate = (resource = "core"): RateInfo | null => rates.get(resource) ?? null;

/** OAuth scopes of the token, from the last X-OAuth-Scopes header (classic PATs only). */
let scopes: string[] | null = null;
export const tokenScopes = (): string[] | null => scopes;

const cache = new Map<string, { at: number; value: unknown }>();

function remember(key: string, value: unknown) {
  cache.delete(key);
  cache.set(key, { at: Date.now(), value });
  while (cache.size > CACHE_MAX) cache.delete(cache.keys().next().value!);
}

function headers(accept: string): Record<string, string> {
  return {
    Accept: accept,
    "User-Agent": "AgentWorker",
    "X-GitHub-Api-Version": "2022-11-28",
    ...(config.githubToken ? { Authorization: `Bearer ${config.githubToken}` } : {}),
  };
}

function readRate(res: Response): RateInfo | null {
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
  rates.set(info.resource ?? "core", info);
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
  const key = `${accept}|${opts.text ? "t" : "j"}|${path}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < (opts.ttlMs ?? TTL_MS)) return hit.value as T;

  const signals = [AbortSignal.timeout(TIMEOUT_MS), ...(opts.signal ? [opts.signal] : [])];
  let res: Response;
  try {
    res = await fetch(`${API}${path}`, { headers: headers(accept), signal: AbortSignal.any(signals) });
  } catch (e) {
    if (opts.signal?.aborted) throw e;
    throw new AppError(504, "upstream_timeout", "GitHub did not answer in time", true);
  }
  const rate = readRate(res);
  const scopeHeader = res.headers.get("x-oauth-scopes");
  if (scopeHeader != null) scopes = scopeHeader.split(",").map((x) => x.trim()).filter(Boolean);
  if (!res.ok) {
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

export const githubEnabled = () => !!config.githubToken;
