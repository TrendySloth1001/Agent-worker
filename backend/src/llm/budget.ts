/**
 * Proactive provider budgets: skip a model BEFORE calling it when the request
 * would not fit its remaining per-minute or per-day allowance, instead of
 * collecting a 429.
 *
 * Two sources are combined, the stricter wins:
 *  - local accounting of every call we made (requests and estimated, later
 *    actual, tokens) against the published free-plan limits, with headroom;
 *  - the provider's own x-ratelimit-* headers (Groq, OpenRouter), minus what
 *    we spent since those headers arrived.
 *
 * Every streamModel call reserves its estimate here and settles it with the
 * real token counts when the stream ends.
 */
import type { Message } from "../providers.js";
import type { ProviderId } from "../models.js";
import { QuotaBlockedError } from "./quota.js";
import { rateSnapshot } from "../usage/rateLimits.js";

export type Limits = { rpm?: number; tpm?: number; rpd?: number; tpd?: number };

/**
 * Published free-plan limits (see routes/usage.ts). "model" scope counts each
 * model separately (Groq), "provider" counts the whole account.
 */
export const PROVIDER_LIMITS: Record<ProviderId, { scope: "model" | "provider"; limits: Limits }> = {
  groq: { scope: "model", limits: { rpm: 30, tpm: 8_000, rpd: 1_000, tpd: 200_000 } },
  nvidia: { scope: "provider", limits: { rpm: 40 } },
  // The daily free-model allowance is tracked from the key endpoint (openrouterKey.ts).
  openrouter: { scope: "provider", limits: { rpm: 20 } },
  // Ollama Cloud publishes no rate, only one request at a time (slots.ts) and a monthly credit (quota.ts).
  ollama: { scope: "provider", limits: {} },
};

/** Local estimates keep this share of each limit free, for estimate error and other processes. */
export const SAFETY = 0.9;
/** Rough tokens one attached image costs on a vision model. */
export const IMAGE_TOKENS = 1_000;
/** Reply tokens reserved when the call sets no (or a huge) max_tokens. */
export const REPLY_RESERVE = 1_500;
const MINUTE = 60_000;

let clock: () => number = Date.now;
/** Test hook. */
export function setBudgetClock(fn: (() => number) | null): void {
  clock = fn ?? Date.now;
}

/** Tokens a request will count against a token window: prompt (text + images) plus a reply reserve. */
export function estimateRequestTokens(messages: Message[], maxTokens?: number): number {
  let chars = 0;
  let images = 0;
  for (const m of messages) {
    chars += m.content.length;
    images += m.images?.length ?? 0;
  }
  return Math.ceil(chars / 3.5) + images * IMAGE_TOKENS + Math.min(maxTokens ?? REPLY_RESERVE, REPLY_RESERVE);
}

// ---- local accounting -----------------------------------------------------------

type Entry = { at: number; tokens: number };
type Counter = { minute: Entry[]; day: string; dayRequests: number; dayTokens: number };

const counters = new Map<string, Counter>();
const utcDay = (ms: number) => new Date(ms).toISOString().slice(0, 10);
const nextUtcDay = (ms: number) => {
  const d = new Date(ms);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1);
};
const providerOf = (id: string) => id.slice(0, id.indexOf(":")) as ProviderId;

/** The key a model's usage counts under: the model itself or its whole provider account. */
export function scopeOf(id: string): string {
  const p = providerOf(id);
  return PROVIDER_LIMITS[p]?.scope === "model" ? id : p;
}

function counter(key: string, now: number): Counter {
  let c = counters.get(key);
  const day = utcDay(now);
  if (!c) {
    c = { minute: [], day, dayRequests: 0, dayTokens: 0 };
    counters.set(key, c);
  }
  if (c.day !== day) Object.assign(c, { day, dayRequests: 0, dayTokens: 0 });
  while (c.minute.length && c.minute[0].at <= now - MINUTE) c.minute.shift();
  return c;
}

export type Reservation = { settle(actualTokens: number | null): void };

/** Counts one call of ~[tokens] on [id] now. settle() replaces the estimate with the real count. */
export function reserve(id: string, tokens: number): Reservation {
  const now = clock();
  const c = counter(scopeOf(id), now);
  const entry: Entry = { at: now, tokens };
  c.minute.push(entry);
  c.dayRequests++;
  c.dayTokens += tokens;
  const day = c.day;
  let settled = false;
  return {
    settle(actual) {
      if (settled || actual === null || !Number.isFinite(actual)) return;
      settled = true;
      const diff = actual - entry.tokens;
      entry.tokens = actual;
      if (c.day === day) c.dayTokens = Math.max(0, c.dayTokens + diff);
    },
  };
}

// ---- the check --------------------------------------------------------------------

export type BudgetReason = "rpm" | "tpm" | "rpd" | "tpd" | "header_tokens" | "header_requests" | "too_large";
export type Verdict = { ok: true } | { ok: false; reason: BudgetReason; waitMs: number };

/**
 * Whether one more call of [tokens] (and [requests] calls of headroom) fits
 * [id]'s windows right now; if not, how long until it would.
 */
export function check(id: string, tokens: number, opts: { requests?: number } = {}): Verdict {
  const now = clock();
  const requests = opts.requests ?? 1;
  const p = providerOf(id);
  const def = PROVIDER_LIMITS[p];
  if (!def) return { ok: true };
  const snap = rateSnapshot(id);
  const c = counter(scopeOf(id), now);
  const l = def.limits;
  // Header limits are the truth for this model once seen (Groq's TPM differs per model).
  const tpm = snap?.limitTokens ?? l.tpm;

  if (tpm && tokens > tpm) return { ok: false, reason: "too_large", waitMs: Number.POSITIVE_INFINITY };

  // Local minute window.
  if (l.rpm && c.minute.length + requests > Math.floor(l.rpm * SAFETY)) {
    const idx = c.minute.length + requests - Math.floor(l.rpm * SAFETY) - 1;
    return { ok: false, reason: "rpm", waitMs: Math.max(0, (c.minute[Math.min(idx, c.minute.length - 1)]?.at ?? now) + MINUTE - now) };
  }
  if (tpm) {
    const cap = Math.floor(tpm * SAFETY);
    let used = c.minute.reduce((n, e) => n + e.tokens, 0);
    if (used + tokens > cap) {
      let waitMs = MINUTE;
      for (const e of c.minute) {
        used -= e.tokens;
        if (used + tokens <= cap) {
          waitMs = e.at + MINUTE - now;
          break;
        }
      }
      return { ok: false, reason: "tpm", waitMs: Math.max(0, waitMs) };
    }
  }
  // Local day window.
  // Groq reports its daily request window in the headers; other providers' request windows are not daily.
  const rpd = (p === "groq" ? snap?.limitRequests : null) ?? l.rpd;
  if (rpd && c.dayRequests + requests > Math.floor(rpd * SAFETY)) return { ok: false, reason: "rpd", waitMs: nextUtcDay(now) - now };
  if (l.tpd && c.dayTokens + tokens > Math.floor(l.tpd * SAFETY)) return { ok: false, reason: "tpd", waitMs: nextUtcDay(now) - now };

  // The provider's own headers, minus what we spent since they arrived.
  if (snap) {
    const at = Date.parse(snap.at);
    const since = c.minute.filter((e) => e.at > at);
    const tokReset = snap.tokensResetAt ? Date.parse(snap.tokensResetAt) : null;
    if (snap.remainingTokens !== null && tokReset !== null && tokReset > now) {
      const left = snap.remainingTokens - since.reduce((n, e) => n + e.tokens, 0);
      if (left < tokens) return { ok: false, reason: "header_tokens", waitMs: tokReset - now };
    }
    const reqReset = snap.resetsAt ? Date.parse(snap.resetsAt) : null;
    if (snap.remainingRequests !== null && reqReset !== null && reqReset > now) {
      const left = snap.remainingRequests - since.length;
      if (left < requests) return { ok: false, reason: "header_requests", waitMs: reqReset - now };
    }
  }
  return { ok: true };
}

/** Thrown instead of a call that would not fit its budget: costs no network, no cooldown (it is a QuotaBlockedError). */
export class BudgetBlockedError extends QuotaBlockedError {
  constructor(
    public modelId: string,
    public reason: BudgetReason | "aux_deferred",
    waitMs: number,
  ) {
    super({ scope: scopeOf(modelId), provider: providerOf(modelId), until: clock() + (Number.isFinite(waitMs) ? waitMs : MINUTE) });
    this.message = `budget: ${modelId} skipped (${reason})`;
  }
}

/** Throws BudgetBlockedError when a call of [tokens] on [id] would not fit right now. */
export function guard(id: string, tokens: number): void {
  const v = check(id, tokens);
  if (v.ok) return;
  noteSkip(id, v.reason);
  throw new BudgetBlockedError(id, v.reason, v.waitMs);
}

// ---- stats for the owner's telemetry -------------------------------------------------

const stats = {
  skips: new Map<string, number>(),
  waits: { count: 0, totalMs: 0 },
  auxDeferred: new Map<string, number>(),
  auxCacheHits: new Map<string, number>(),
  userCaps: new Map<string, number>(),
};
const bump = (m: Map<string, number>, k: string) => m.set(k, (m.get(k) ?? 0) + 1);

export const noteSkip = (id: string, reason: string) => bump(stats.skips, `${id}|${reason}`);
export const noteWait = (ms: number) => {
  stats.waits.count++;
  stats.waits.totalMs += ms;
};
export const noteAuxDeferred = (purpose: string) => bump(stats.auxDeferred, purpose);
export const noteAuxCacheHit = (purpose: string) => bump(stats.auxCacheHits, purpose);
export const noteUserCap = (route: string) => bump(stats.userCaps, route);

export type BudgetRow = {
  scope: string;
  minute: { requests: number; tokens: number; rpm: number | null; tpm: number | null };
  day: { requests: number; tokens: number; rpd: number | null; tpd: number | null };
};

/** Live budgets and skip counters (owner-only telemetry). */
export function budgetSnapshot(): {
  scopes: BudgetRow[];
  skips: Array<{ model: string; reason: string; count: number }>;
  waits: { count: number; totalMs: number };
  auxDeferred: Record<string, number>;
  auxCacheHits: Record<string, number>;
  userCaps: Record<string, number>;
} {
  const now = clock();
  const scopes: BudgetRow[] = [];
  for (const key of [...counters.keys()].sort()) {
    const c = counter(key, now);
    const def = PROVIDER_LIMITS[providerOf(key.includes(":") ? key : `${key}:`)];
    const snap = key.includes(":") ? rateSnapshot(key) : null;
    scopes.push({
      scope: key,
      minute: { requests: c.minute.length, tokens: c.minute.reduce((n, e) => n + e.tokens, 0), rpm: def?.limits.rpm ?? null, tpm: snap?.limitTokens ?? def?.limits.tpm ?? null },
      day: { requests: c.dayRequests, tokens: c.dayTokens, rpd: (key.startsWith("groq:") ? snap?.limitRequests : null) ?? def?.limits.rpd ?? null, tpd: def?.limits.tpd ?? null },
    });
  }
  return {
    scopes,
    skips: [...stats.skips].map(([k, count]) => {
      const i = k.lastIndexOf("|");
      return { model: k.slice(0, i), reason: k.slice(i + 1), count };
    }),
    waits: { ...stats.waits },
    auxDeferred: Object.fromEntries(stats.auxDeferred),
    auxCacheHits: Object.fromEntries(stats.auxCacheHits),
    userCaps: Object.fromEntries(stats.userCaps),
  };
}

/** Test hook. */
export function resetBudget(): void {
  counters.clear();
  for (const m of [stats.skips, stats.auxDeferred, stats.auxCacheHits, stats.userCaps]) m.clear();
  stats.waits = { count: 0, totalMs: 0 };
}

/** Waits [ms] (abortable). */
export function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(new DOMException("aborted", "AbortError"));
    const t = setTimeout(() => {
      signal?.removeEventListener("abort", onAbort);
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(t);
      reject(new DOMException("aborted", "AbortError"));
    };
    signal?.addEventListener("abort", onAbort, { once: true });
  });
}
