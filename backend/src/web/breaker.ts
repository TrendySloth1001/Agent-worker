/**
 * Per-provider circuit breaker. After `threshold` consecutive failures
 * (429, 5xx, timeouts) a provider is skipped for a cooldown that doubles each
 * time it trips again; after the cooldown one probe request is let through
 * (half-open), and its outcome closes or re-opens the circuit.
 */
export type BreakerState = "closed" | "open" | "half-open";

type Entry = { fails: number; trips: number; openUntil: number; probing: number };

export class CircuitBreaker {
  private entries = new Map<string, Entry>();
  constructor(
    private opts: { threshold?: number; cooldownMs?: number; maxCooldownMs?: number; probeTimeoutMs?: number; now?: () => number } = {},
  ) {}

  private now() {
    return (this.opts.now ?? Date.now)();
  }
  private entry(name: string): Entry {
    let e = this.entries.get(name);
    if (!e) this.entries.set(name, (e = { fails: 0, trips: 0, openUntil: 0, probing: 0 }));
    return e;
  }

  state(name: string): BreakerState {
    const e = this.entries.get(name);
    if (!e || e.openUntil === 0) return "closed";
    return this.now() < e.openUntil ? "open" : "half-open";
  }

  /** Whether a request may go out now. In half-open state only one probe at a time. */
  allow(name: string): boolean {
    const s = this.state(name);
    if (s === "closed") return true;
    if (s === "open") return false;
    const e = this.entry(name);
    const t = this.now();
    if (e.probing && t - e.probing < (this.opts.probeTimeoutMs ?? 15_000)) return false;
    e.probing = t;
    return true;
  }

  success(name: string): void {
    const e = this.entries.get(name);
    if (!e) return;
    e.fails = 0;
    e.trips = 0;
    e.openUntil = 0;
    e.probing = 0;
  }

  /** `hard` (auth/forbidden) opens at once; `retryAfterMs` is honoured as the minimum cooldown. */
  failure(name: string, o: { hard?: boolean; retryAfterMs?: number } = {}): void {
    const e = this.entry(name);
    const wasProbe = e.probing > 0;
    e.probing = 0;
    e.fails++;
    if (!(o.hard || wasProbe || e.fails >= (this.opts.threshold ?? 3))) return;
    e.trips++;
    const base = this.opts.cooldownMs ?? 60_000;
    const max = this.opts.maxCooldownMs ?? 10 * 60_000;
    let cooldown = Math.min(max, base * 2 ** (e.trips - 1));
    if (o.hard) cooldown = Math.max(cooldown, Math.min(max, base * 5));
    if (o.retryAfterMs) cooldown = Math.max(cooldown, Math.min(max, o.retryAfterMs));
    e.openUntil = this.now() + cooldown;
  }

  snapshot(): Record<string, { state: BreakerState; fails: number }> {
    const out: Record<string, { state: BreakerState; fails: number }> = {};
    for (const [k, e] of this.entries) out[k] = { state: this.state(k), fails: e.fails };
    return out;
  }
}
