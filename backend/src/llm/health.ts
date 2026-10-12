/**
 * Circuit breaker for models. Consecutive transient failures (timeouts, stalls,
 * empty or truncated streams, 5xx) open the circuit for an exponentially
 * growing time; Auto skips an open model. When the time is up the model is
 * tried again (half-open): one success closes the circuit, one more failure
 * doubles the wait.
 */
export const BASE_COOLDOWN_MS = 30_000;
export const MAX_COOLDOWN_MS = 10 * 60_000;
/** A failure streak older than this is forgotten (the model had a long quiet spell). */
const STREAK_FORGET_MS = 30 * 60_000;

type State = { failures: number; openUntil: number; lastFailureAt: number };

export class HealthTracker {
  private state = new Map<string, State>();
  constructor(private now: () => number = Date.now) {}

  /** Cooldown after the n-th consecutive failure: 30 s, 60 s, 2 min, ... capped at 10 min. */
  static backoff(failures: number): number {
    return Math.min(BASE_COOLDOWN_MS * 2 ** Math.max(0, failures - 1), MAX_COOLDOWN_MS);
  }

  /** Records a failure and returns how long the model should be skipped (ms). */
  failure(id: string): number {
    const t = this.now();
    const prev = this.state.get(id);
    const failures = prev && t - prev.lastFailureAt < STREAK_FORGET_MS ? prev.failures + 1 : 1;
    const ms = HealthTracker.backoff(failures);
    this.state.set(id, { failures, openUntil: t + ms, lastFailureAt: t });
    return ms;
  }

  success(id: string): void {
    this.state.delete(id);
  }

  /** True while the circuit is open (the model is considered dead). */
  isOpen(id: string): boolean {
    const s = this.state.get(id);
    return !!s && s.openUntil > this.now();
  }

  consecutiveFailures(id: string): number {
    return this.state.get(id)?.failures ?? 0;
  }
}

export const health = new HealthTracker();
