import { config } from "../config.js";

export type GithubInfo = {
  login: string | null;
  limit: number | null;
  remaining: number | null;
  resetsAt: string | null;
  error: string | null;
};

let cached: { at: number; value: GithubInfo } | null = null;
const TTL_MS = 60_000;

/** Who the token belongs to and its hourly REST quota (used by knowledge ingestion). */
export async function getGithubInfo(): Promise<GithubInfo | null> {
  if (!config.githubToken) return null;
  if (cached && Date.now() - cached.at < TTL_MS) return cached.value;
  const headers = { Authorization: `Bearer ${config.githubToken}`, "User-Agent": "AgentWorker", Accept: "application/vnd.github+json" };
  let value: GithubInfo;
  try {
    const [rate, user] = await Promise.all([
      fetch("https://api.github.com/rate_limit", { headers, signal: AbortSignal.timeout(8000) }),
      fetch("https://api.github.com/user", { headers, signal: AbortSignal.timeout(8000) }),
    ]);
    if (!rate.ok) throw new Error(rate.status === 401 ? "Token rejected" : `GitHub ${rate.status}`);
    const core = ((await rate.json()) as any)?.resources?.core ?? {};
    const login = user.ok ? (((await user.json()) as any)?.login ?? null) : null;
    value = {
      login,
      limit: core.limit ?? null,
      remaining: core.remaining ?? null,
      resetsAt: core.reset ? new Date(core.reset * 1000).toISOString() : null,
      error: null,
    };
  } catch (e) {
    value = { login: null, limit: null, remaining: null, resetsAt: null, error: (e as Error).message.slice(0, 120) };
  }
  cached = { at: Date.now(), value };
  return value;
}
