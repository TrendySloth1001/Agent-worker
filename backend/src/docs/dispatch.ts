// Spreads section writers over providers by live headroom.
//
// Each section is written by ONE small/fast model chosen when the section
// starts: the provider with the fewest requests in flight (cap per provider),
// then the least recently used, among those whose per-minute budget still
// fits the request. A failure (429, timeout, empty answer) burns that model's
// rate-limit scope for a while and the section moves to ANOTHER provider
// rather than retrying the same one.
import { check as budgetCheck, scopeOf } from "../llm/budget.js";
import { isQuotaBlocked } from "../llm/quota.js";
import { cooldownFor } from "../llm/router.js";

export type Headroom = { ok: true } | { ok: false; waitMs: number };

export type PoolDeps = {
  headroom: (model: string, tokens: number) => Headroom;
  now: () => number;
  sleep: (ms: number, signal?: AbortSignal) => Promise<void>;
};

export const realSleep = (ms: number, signal?: AbortSignal) =>
  new Promise<void>((resolve, reject) => {
    if (signal?.aborted) return reject(new DOMException("aborted", "AbortError"));
    const t = setTimeout(resolve, ms);
    signal?.addEventListener("abort", () => (clearTimeout(t), reject(new DOMException("aborted", "AbortError"))), { once: true });
  });

/** Live headroom from the router's own accounting: minute/day budget, cooldowns, quota blocks. */
export const liveHeadroom = (model: string, tokens: number): Headroom => {
  if (isQuotaBlocked(model)) return { ok: false, waitMs: 60_000 };
  const cool = cooldownFor(model);
  if (cool !== null) return { ok: false, waitMs: Math.max(0, cool - Date.now()) };
  const v = budgetCheck(model, tokens);
  return v.ok ? { ok: true } : { ok: false, waitMs: Math.min(v.waitMs, 60_000) };
};

export const defaultPoolDeps: PoolDeps = { headroom: liveHeadroom, now: Date.now, sleep: realSleep };

const providerOf = (id: string) => id.slice(0, id.indexOf(":"));

export type PoolOptions = {
  /** Requests in flight per provider. */
  perProvider?: number;
  /** How long a failed model's rate-limit scope is avoided. */
  burnMs?: number;
  /** The longest a section waits for headroom before going ahead anyway. */
  maxWaitMs?: number;
  /** Models tried per section (each on another provider where possible). */
  attempts?: number;
};

export class WriterPool {
  private inFlight = new Map<string, number>();
  private lastUsed = new Map<string, number>();
  private burned = new Map<string, number>();
  private readonly perProvider: number;
  private readonly burnMs: number;
  private readonly maxWaitMs: number;
  private readonly attempts: number;
  /** Counters for the simulation and logs. */
  stats = { calls: 0, failures: 0, waits: 0 };

  constructor(
    /** Writer models, preferred first. */
    readonly models: string[],
    opts: PoolOptions = {},
    private readonly deps: PoolDeps = defaultPoolDeps,
  ) {
    this.perProvider = opts.perProvider ?? 2;
    this.burnMs = opts.burnMs ?? 30_000;
    this.maxWaitMs = opts.maxWaitMs ?? 20_000;
    this.attempts = opts.attempts ?? 3;
  }

  /** How many sections can run at once. */
  get capacity(): number {
    return new Set(this.models.map(providerOf)).size * this.perProvider;
  }

  private isBurned(model: string): boolean {
    const until = this.burned.get(scopeOf(model));
    return until !== undefined && until > this.deps.now();
  }

  /** The best free model for [tokens], or the shortest wait until one frees up. */
  private pick(tokens: number, excluded: Set<string>): { model: string } | { waitMs: number } {
    // When every candidate is burned, waiting helps nobody: go on with them (the provider decides).
    const open = this.models.filter((m) => !excluded.has(m));
    const allBurned = open.length > 0 && open.every((m) => this.isBurned(m));
    let wait = Number.POSITIVE_INFINITY;
    let best: { model: string; load: number; used: number; idx: number } | null = null;
    this.models.forEach((model, idx) => {
      if (excluded.has(model)) return;
      const p = providerOf(model);
      const load = this.inFlight.get(p) ?? 0;
      if (load >= this.perProvider) return void (wait = Math.min(wait, 250));
      if (!allBurned && this.isBurned(model)) return void (wait = Math.min(wait, (this.burned.get(scopeOf(model)) ?? 0) - this.deps.now()));
      const h = this.deps.headroom(model, tokens);
      if (!h.ok) return void (wait = Math.min(wait, Math.max(h.waitMs, 100)));
      const cand = { model, load, used: this.lastUsed.get(p) ?? 0, idx };
      if (!best || cand.load < best.load || (cand.load === best.load && (cand.used < best.used || (cand.used === best.used && cand.idx < best.idx)))) best = cand;
    });
    return best ? { model: (best as { model: string }).model } : { waitMs: Number.isFinite(wait) ? wait : 500 };
  }

  /**
   * Runs [exec] on the best model. A failure moves on to another model
   * (other provider first); the last error is thrown after [attempts].
   */
  async run<T>(tokens: number, exec: (model: string, attempt: number) => Promise<T>, signal: AbortSignal): Promise<{ value: T; model: string }> {
    const tried = new Set<string>();
    let last: unknown = new Error("no writer model available");
    for (let attempt = 0; attempt < this.attempts; attempt++) {
      let waited = 0;
      let model: string | null = null;
      for (;;) {
        if (signal.aborted) throw new DOMException("aborted", "AbortError");
        // Providers already tried for this section come last.
        const excluded = new Set(this.models.filter((m) => tried.has(m)));
        let r = this.pick(tokens, excluded);
        if ("waitMs" in r && excluded.size && waited >= this.maxWaitMs) r = this.pick(tokens, new Set());
        if ("model" in r) {
          model = r.model;
          break;
        }
        if (waited >= this.maxWaitMs) {
          // Out of patience: take the least loaded model that is not known-bad, headroom or not.
          model = this.models.find((m) => !tried.has(m) && !this.isBurned(m) && (this.inFlight.get(providerOf(m)) ?? 0) < this.perProvider) ?? null;
          if (model) break;
        }
        const ms = Math.min(Math.max(r.waitMs, 50), 1_000, Math.max(this.maxWaitMs - waited, 50));
        this.stats.waits++;
        await this.deps.sleep(ms, signal);
        waited += ms;
        if (waited > this.maxWaitMs * 3) throw last;
      }
      const p = providerOf(model);
      this.inFlight.set(p, (this.inFlight.get(p) ?? 0) + 1);
      this.lastUsed.set(p, this.deps.now());
      this.stats.calls++;
      try {
        return { value: await exec(model, attempt), model };
      } catch (e) {
        if (signal.aborted) throw e;
        last = e;
        this.stats.failures++;
        tried.add(model);
        this.burned.set(scopeOf(model), this.deps.now() + this.burnMs);
      } finally {
        this.inFlight.set(p, Math.max(0, (this.inFlight.get(p) ?? 1) - 1));
      }
    }
    throw last;
  }
}
