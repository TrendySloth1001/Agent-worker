import { config } from "../config.js";

export type OpenRouterKeyInfo = {
  used: number | null;
  limit: number | null;
  remaining: number | null;
  isFreeTier: boolean | null;
  fetchedAt: string;
};

const TTL_MS = 60_000;
let cached: { info: OpenRouterKeyInfo; at: number } | null = null;
let inflight: Promise<void> | null = null;
let lastFailed = false;

async function refresh() {
  try {
    const res = await fetch("https://openrouter.ai/api/v1/key", {
      headers: { Authorization: `Bearer ${config.openrouterApiKey}` },
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = ((await res.json()) as any)?.data ?? {};
    const free = data.free_model_daily_requests;
    const isFree = typeof data.is_free_tier === "boolean" ? data.is_free_tier : null;
    cached = {
      at: Date.now(),
      info: {
        used: free ? (free.used ?? null) : null,
        limit: free ? (free.limit ?? null) : null,
        remaining: free ? (free.remaining ?? null) : null,
        isFreeTier: isFree,
        fetchedAt: new Date().toISOString(),
      },
    };
    lastFailed = false;
  } catch {
    lastFailed = true;
    if (cached) cached.at = Date.now() - TTL_MS + 10_000; // retry in 10 s, keep serving last good
  }
}

/** Cached for 60 s. On failure returns the last good value with stale=true, or info=null. */
export async function getOpenRouterKeyInfo(): Promise<{ info: OpenRouterKeyInfo | null; stale: boolean }> {
  if (!config.openrouterApiKey) return { info: null, stale: true };
  if (!cached || Date.now() - cached.at > TTL_MS) {
    inflight ??= refresh().finally(() => (inflight = null));
    await inflight;
  }
  return { info: cached?.info ?? null, stale: lastFailed };
}

/** Count a request locally between polls so Auto notices an exhausted quota promptly. */
export function noteOpenRouterFreeRequest() {
  const i = cached?.info;
  if (i && i.used !== null && i.remaining !== null) {
    i.used += 1;
    i.remaining = Math.max(0, i.remaining - 1);
  }
}
