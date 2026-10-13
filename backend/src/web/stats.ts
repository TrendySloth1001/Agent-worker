// In-memory per-provider web search counters for the owner telemetry: call
// volume, cache hit rate, empty-result rate, error rate and latency
// percentiles since the process started. The durable per-call record is the
// usage table (provider "web", model = provider name).

type Counter = { calls: number; ok: number; empty: number; errors: number; cached: number; skipped: number; results: number; lastError?: string; lastErrorAt?: number; lat: number[] };

const LAT_KEEP = 200;
const stats = new Map<string, Counter>();
let research = { runs: 0, cached: 0, empty: 0, earlyReturn: 0, ms: [] as number[] };

const entry = (p: string): Counter => {
  let c = stats.get(p);
  if (!c) stats.set(p, (c = { calls: 0, ok: 0, empty: 0, errors: 0, cached: 0, skipped: 0, results: 0, lat: [] }));
  return c;
};

const pushLat = (arr: number[], ms: number) => {
  arr.push(ms);
  if (arr.length > LAT_KEEP) arr.shift();
};

export type ProviderOutcome = { provider: string; candidates: unknown[]; ms: number; cached?: boolean; skipped?: string; error?: string };

export function recordOutcome(o: ProviderOutcome): void {
  const c = entry(o.provider);
  if (o.skipped) return void c.skipped++;
  if (o.cached) return void c.cached++;
  c.calls++;
  if (o.error) {
    if (o.error === "aborted") return;
    c.errors++;
    c.lastError = o.error;
    c.lastErrorAt = Date.now();
    return;
  }
  c.ok++;
  c.results += o.candidates.length;
  if (!o.candidates.length) c.empty++;
  pushLat(c.lat, o.ms);
}

export function recordResearch(r: { ms: number; cached?: boolean; results: number; early?: boolean }): void {
  research.runs++;
  if (r.cached) research.cached++;
  if (!r.results) research.empty++;
  if (r.early) research.earlyReturn++;
  if (!r.cached) pushLat(research.ms, r.ms);
}

function pct(arr: number[], p: number): number | null {
  if (!arr.length) return null;
  const s = [...arr].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.floor((p / 100) * s.length))];
}

const rate = (n: number, d: number) => (d ? Math.round((n / d) * 1000) / 1000 : null);

export type ProviderStats = {
  provider: string;
  calls: number;
  cacheHitRate: number | null;
  emptyRate: number | null;
  errorRate: number | null;
  skipped: number;
  avgResults: number | null;
  p50Ms: number | null;
  p95Ms: number | null;
  lastError: string | null;
  lastErrorAt: string | null;
};

export function webStats(): { providers: ProviderStats[]; research: { runs: number; cacheHitRate: number | null; emptyRate: number | null; earlyReturnRate: number | null; p50Ms: number | null; p95Ms: number | null } } {
  const providers = [...stats].map(([provider, c]) => ({
    provider,
    calls: c.calls,
    cacheHitRate: rate(c.cached, c.calls + c.cached),
    emptyRate: rate(c.empty, c.ok),
    errorRate: rate(c.errors, c.calls),
    skipped: c.skipped,
    avgResults: c.ok ? Math.round((c.results / c.ok) * 10) / 10 : null,
    p50Ms: pct(c.lat, 50),
    p95Ms: pct(c.lat, 95),
    lastError: c.lastError ?? null,
    lastErrorAt: c.lastErrorAt ? new Date(c.lastErrorAt).toISOString() : null,
  }));
  return {
    providers: providers.sort((a, b) => b.calls - a.calls),
    research: {
      runs: research.runs,
      cacheHitRate: rate(research.cached, research.runs),
      emptyRate: rate(research.empty, research.runs),
      earlyReturnRate: rate(research.earlyReturn, research.runs - research.cached),
      p50Ms: pct(research.ms, 50),
      p95Ms: pct(research.ms, 95),
    },
  };
}

/** Test hook. */
export function resetWebStats(): void {
  stats.clear();
  research = { runs: 0, cached: 0, empty: 0, earlyReturn: 0, ms: [] };
}
