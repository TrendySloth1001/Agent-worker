import "server-only";
import { upstreamSessionSchema } from "@/lib/api/schemas";
import type { SessionTokens } from "./session-cookies";
import type { SessionStore } from "./session-store";

export interface UpstreamDeps {
  apiUrl: string;
  fetch: typeof fetch;
  device: string;
}

type RefreshOutcome =
  { kind: "ok"; tokens: SessionTokens } | { kind: "revoked" } | { kind: "failed" };

const GRACE_MS = 10_000;
const inflight = new Map<string, Promise<RefreshOutcome>>();

async function requestRefresh(refreshToken: string, deps: UpstreamDeps): Promise<RefreshOutcome> {
  let res: Response;
  try {
    res = await deps.fetch(`${deps.apiUrl}/auth/refresh`, {
      method: "POST",
      headers: { "content-type": "application/json", "user-agent": deps.device },
      body: JSON.stringify({ refreshToken, device: deps.device }),
      cache: "no-store",
    });
  } catch {
    return { kind: "failed" };
  }
  if (res.status === 401) return { kind: "revoked" };
  if (!res.ok) return { kind: "failed" };
  const parsed = upstreamSessionSchema.safeParse(await res.json().catch(() => null));
  if (!parsed.success) return { kind: "failed" };
  const { accessToken, accessExpiresAt, refreshToken: next, refreshExpiresAt } = parsed.data;
  return {
    kind: "ok",
    tokens: { accessToken, accessExpiresAt, refreshToken: next, refreshExpiresAt },
  };
}

function singleFlight(refreshToken: string, deps: UpstreamDeps): Promise<RefreshOutcome> {
  const existing = inflight.get(refreshToken);
  if (existing) return existing;
  const pending = requestRefresh(refreshToken, deps);
  inflight.set(refreshToken, pending);
  // A rotated token must not be replayed by a request that raced the first refresh.
  void pending.finally(() => setTimeout(() => inflight.delete(refreshToken), GRACE_MS).unref());
  return pending;
}

export async function refreshSession(
  store: SessionStore,
  deps: UpstreamDeps,
): Promise<SessionTokens | null> {
  const { refreshToken } = store.read();
  if (!refreshToken) return null;
  const outcome = await singleFlight(refreshToken, deps);
  if (outcome.kind === "ok") {
    store.write(outcome.tokens);
    return outcome.tokens;
  }
  if (outcome.kind === "revoked") store.clear();
  return null;
}
