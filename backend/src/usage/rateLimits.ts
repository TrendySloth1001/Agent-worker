/** Latest rate-limit headers seen per "provider:model", e.g. Groq's daily request quota. */
export type RateSnapshot = {
  limitRequests: number | null;
  remainingRequests: number | null;
  /** When the request window fully resets. */
  resetsAt: string | null;
  limitTokens: number | null;
  remainingTokens: number | null;
  at: string;
};

const snapshots = new Map<string, RateSnapshot>();

const int = (v: string | null) => {
  const n = v === null ? NaN : Number(v);
  return Number.isFinite(n) ? n : null;
};

/** Parses durations like "1m26.4s", "3.42s", "2h0m0s", "850ms". */
function durationMs(v: string | null): number | null {
  if (!v) return null;
  let total = 0;
  let matched = false;
  for (const [, num, unit] of v.matchAll(/([\d.]+)(ms|h|m|s)/g)) {
    matched = true;
    total += Number(num) * ({ h: 3_600_000, m: 60_000, s: 1000, ms: 1 } as Record<string, number>)[unit];
  }
  return matched ? total : null;
}

export function recordRateHeaders(id: string, headers: Headers): void {
  const limitRequests = int(headers.get("x-ratelimit-limit-requests"));
  if (limitRequests === null && headers.get("x-ratelimit-limit-tokens") === null) return;
  const reset = durationMs(headers.get("x-ratelimit-reset-requests"));
  snapshots.set(id, {
    limitRequests,
    remainingRequests: int(headers.get("x-ratelimit-remaining-requests")),
    resetsAt: reset === null ? null : new Date(Date.now() + reset).toISOString(),
    limitTokens: int(headers.get("x-ratelimit-limit-tokens")),
    remainingTokens: int(headers.get("x-ratelimit-remaining-tokens")),
    at: new Date().toISOString(),
  });
}

export function rateSnapshots(prefix: string): Array<[string, RateSnapshot]> {
  return [...snapshots].filter(([id]) => id.startsWith(prefix));
}
