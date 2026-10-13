/**
 * Provider quota and rate-limit awareness for every upstream LLM call.
 *
 * A failed call is classified as one of:
 *  - quota_exhausted: the account (or one model) has used up a monthly, weekly,
 *    daily or billing allowance ("you have reached your monthly usage limit",
 *    OpenRouter 402 / free-models-per-day, Groq "requests per day"). The scope
 *    is skipped until the window resets (next UTC month / day, else 6 h); one
 *    cheap background probe per probe interval checks whether it came back early.
 *  - rate_limited: a short per-minute window; honours Retry-After and "try again in".
 *  - upstream_busy: OpenRouter's free upstream is saturated ("Provider returned
 *    error"): move on at once, short cooldown for that model only.
 *  - auth / transient / other: handled by the router's cooldowns and breaker.
 *
 * Quota state lives in memory and is mirrored into the shared web_cache table
 * (key prefix "llm-quota|") so a restart does not forget an exhausted month.
 */
import { MODELS, clearCooldown, setCooldown, type ProviderId } from "../models.js";
import { UpstreamError } from "../providers.js";
import { db, isDbUp } from "../db/prisma.js";
import { log } from "../util/logger.js";
import { usesUserKey } from "../keys/store.js";

export type QuotaWindow = "month" | "week" | "day" | "hour" | "unknown";

export type ErrorClass =
  | { kind: "quota_exhausted"; window: QuotaWindow; scope: "provider" | "model"; untilMs: number }
  | { kind: "rate_limited"; cooldownMs: number }
  | { kind: "upstream_busy"; cooldownMs: number }
  | { kind: "auth"; cooldownMs: number }
  | { kind: "transient" }
  | { kind: "blocked" }
  | { kind: "other" };

const HOUR = 3_600_000;
const DEFAULT_QUOTA_MS = 6 * HOUR;
const RATE_LIMIT_DEFAULT_MS = 60_000;
const BUSY_COOLDOWN_MS = 30_000;
const AUTH_COOLDOWN_MS = HOUR;
/** How often an exhausted scope may be re-probed with one cheap call. */
const PROBE_EVERY_MS: Record<QuotaWindow, number> = { month: 6 * HOUR, week: 6 * HOUR, day: HOUR, hour: 15 * 60_000, unknown: HOUR };

export const PROVIDER_NAMES: Record<ProviderId, string> = { ollama: "Ollama", openrouter: "OpenRouter", groq: "Groq", nvidia: "NVIDIA" };

/** Account-wide allowances: a quota error from one model blocks the whole provider. */
const ACCOUNT_SCOPED = new Set<string>(["ollama", "openrouter"]);

export const nextUtcMonthStart = (now: number): number => {
  const d = new Date(now);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1);
};
export const nextUtcDayStart = (now: number): number => {
  const d = new Date(now);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1);
};

/** "Please try again in 1m26.4s" / "try again in 7.5s" / "retry after 30 seconds" → ms. */
export function retryHintMs(message: string): number | undefined {
  const m = message.match(/(?:try again|retry)(?: after| in)\s+((?:[\d.]+\s*(?:ms|h|m|s|seconds?|minutes?|hours?)\s*)+)/i);
  if (!m) return undefined;
  let total = 0;
  for (const [, num, unit] of m[1].matchAll(/([\d.]+)\s*(ms|h|m|s|seconds?|minutes?|hours?)/gi)) {
    const u = unit.toLowerCase();
    const mult = u === "ms" ? 1 : u.startsWith("h") ? HOUR : u === "m" || u.startsWith("min") ? 60_000 : 1000;
    total += Number(num) * mult;
  }
  return total > 0 ? Math.ceil(total) : undefined;
}

const PER_MINUTE = /per[- ]minute|\b(TPM|RPM)\b|tokens per min|requests per min/i;
const MONTHLY = /monthly|per[- ]month|this month/i;
const WEEKLY = /weekly|per[- ]week/i;
const DAILY = /daily|per[- ]day|free-models-per-day|\b(RPD|TPD)\b/i;
const HOURLY = /hourly|per[- ]hour|session usage limit/i;
const QUOTA = /usage limit|quota|insufficient (credits|balance|funds)|more credits|credit balance|billing|payment required|out of credits|free-models-per|requests per day|tokens per day|\b(RPD|TPD)\b|daily limit|monthly limit/i;

/** Classifies an upstream failure for model [id] ("provider:model"). */
export function classifyError(id: string, e: Pick<UpstreamError, "status" | "message" | "retryAfterMs">, now = Date.now()): ErrorClass {
  if (e instanceof QuotaBlockedError) return { kind: "blocked" };
  const provider = id.slice(0, id.indexOf(":"));
  const msg = e.message ?? "";
  const status = e.status;
  const hint = e.retryAfterMs ?? retryHintMs(msg);

  // Our allowance is used up (402 is always billing; 403/429 only with quota wording, never a per-minute window).
  const quotaWording = QUOTA.test(msg) && !PER_MINUTE.test(msg);
  if (status === 402 || ((status === 429 || status === 403) && quotaWording)) {
    const window: QuotaWindow = MONTHLY.test(msg) ? "month" : WEEKLY.test(msg) ? "week" : DAILY.test(msg) ? "day" : HOURLY.test(msg) ? "hour" : "unknown";
    const reset =
      window === "month" ? nextUtcMonthStart(now) : window === "day" ? nextUtcDayStart(now) : window === "week" ? now + 7 * 24 * HOUR : window === "hour" ? now + HOUR : now + DEFAULT_QUOTA_MS;
    // A precise hint from the provider (Groq's rolling day window, Retry-After) wins when it is sooner.
    const untilMs = hint && now + hint < reset ? now + hint : reset;
    const billing = status === 402 || /credits|billing|payment|balance|funds/i.test(msg);
    const scope = ACCOUNT_SCOPED.has(provider) || billing ? "provider" : "model";
    return { kind: "quota_exhausted", window, scope, untilMs };
  }
  // A free OpenRouter model's own upstream is saturated: not our quota, try the next model now.
  if (provider === "openrouter" && (status === 429 || status >= 500) && /provider returned error/i.test(msg)) {
    return { kind: "upstream_busy", cooldownMs: BUSY_COOLDOWN_MS };
  }
  if (status === 429) return { kind: "rate_limited", cooldownMs: Math.max(1_000, hint ?? RATE_LIMIT_DEFAULT_MS) };
  if (status === 401 || status === 403 || status === 404) return { kind: "auth", cooldownMs: AUTH_COOLDOWN_MS };
  if (status === 0 || status >= 500) return { kind: "transient" };
  return { kind: "other" };
}

// ---- state ----------------------------------------------------------------------

type Block = {
  /** "ollama" (whole provider) or "groq:qwen/qwen3.8-27b" (one model). */
  scope: string;
  provider: string;
  window: QuotaWindow;
  until: number;
  since: number;
  nextProbeAt: number;
  probing: boolean;
  /** Model used for the cheap probe call. */
  probeModel: string;
};

const blocks = new Map<string, Block>();

/** Thrown instead of calling a provider whose quota is known to be exhausted (no network, no wasted seconds). */
export class QuotaBlockedError extends UpstreamError {
  constructor(public block: { scope: string; provider: string; until: number }) {
    super(429, `${PROVIDER_NAMES[block.provider as ProviderId] ?? block.provider} quota exhausted until ${new Date(block.until).toISOString()}`);
  }
}

type Prober = (modelId: string) => Promise<void>;
let prober: Prober | null = null;
/** The router registers a cheap one-token call used to re-probe an exhausted scope. */
export function setQuotaProber(p: Prober | null): void {
  prober = p;
}

let clock: () => number = Date.now;
/** Test hook. */
export function setQuotaClock(fn: (() => number) | null): void {
  clock = fn ?? Date.now;
}

const affectedModels = (b: Pick<Block, "scope" | "provider">) => (b.scope === b.provider ? MODELS.filter((m) => m.provider === b.provider).map((m) => m.id) : [b.scope]);

function expire(key: string, b: Block, now: number): boolean {
  if (b.until > now) return false;
  blocks.delete(key);
  log.info("provider quota window over", { provider: b.provider, scope: b.scope, window: b.window });
  return true;
}

/** The exhausted-quota block that covers model [id], or null. May kick off a background re-probe. */
export function quotaBlock(id: string): { scope: string; provider: string; window: QuotaWindow; until: number } | null {
  const provider = id.slice(0, id.indexOf(":"));
  // The server's exhausted quota says nothing about a key the caller brought themselves.
  if (usesUserKey(provider)) return null;
  const now = clock();
  for (const key of [provider, id]) {
    const b = blocks.get(key);
    if (!b || expire(key, b, now)) continue;
    maybeProbe(b, now);
    return { scope: b.scope, provider: b.provider, window: b.window, until: b.until };
  }
  return null;
}

export const isQuotaBlocked = (id: string): boolean => quotaBlock(id) !== null;

/** Throws QuotaBlockedError when [id] must not be called right now. */
export function quotaGuard(id: string): void {
  const b = quotaBlock(id);
  if (b) throw new QuotaBlockedError(b);
}

function maybeProbe(b: Block, now: number): void {
  if (!prober || b.probing || now < b.nextProbeAt) return;
  b.probing = true;
  b.nextProbeAt = now + PROBE_EVERY_MS[b.window];
  const run = prober;
  void run(b.probeModel)
    .then(() => {
      if (blocks.get(b.scope) === b) clearQuota(b.probeModel, "probe");
    })
    .catch((e) => {
      // Still exhausted (or unreachable): stay blocked until the next probe or the window end.
      if (e instanceof UpstreamError) {
        const c = classifyError(b.probeModel, e, clock());
        if (c.kind === "quota_exhausted") b.until = Math.max(b.until, c.untilMs);
      }
    })
    .finally(() => {
      b.probing = false;
    });
}

/** Records an exhausted quota for [id]'s scope. Logs once per transition. */
export function markQuota(id: string, c: Extract<ErrorClass, { kind: "quota_exhausted" }>, message = ""): void {
  const provider = id.slice(0, id.indexOf(":"));
  const scope = c.scope === "provider" ? provider : id;
  const now = clock();
  const prev = blocks.get(scope);
  if (prev && prev.until > now) {
    prev.until = Math.max(prev.until, c.untilMs);
    return;
  }
  const probeModel = c.scope === "provider" ? (PROBE_MODELS[provider] ?? id) : id;
  const b: Block = { scope, provider, window: c.window, until: c.untilMs, since: now, nextProbeAt: now + PROBE_EVERY_MS[c.window], probing: false, probeModel };
  blocks.set(scope, b);
  for (const m of affectedModels(b)) setCooldown(m, Math.max(0, b.until - Date.now()));
  log.warn("provider quota exhausted", { provider, scope, window: c.window, until: new Date(b.until).toISOString(), message: message.slice(0, 160) });
  persist(b);
}

/** A call on [id] succeeded: any quota block covering it is over. */
export function clearQuota(id: string, via: "success" | "probe" = "success"): void {
  const provider = id.slice(0, id.indexOf(":"));
  for (const key of [provider, id]) {
    const b = blocks.get(key);
    if (!b) continue;
    blocks.delete(key);
    for (const m of affectedModels(b)) clearCooldown(m);
    log.info("provider quota restored", { provider, scope: b.scope, via });
    unpersist(key);
  }
}

/** Cheapest model per provider for re-probing an account-wide block. */
const PROBE_MODELS: Record<string, string> = {
  ollama: "ollama:gpt-oss:20b",
  openrouter: "openrouter:google/gemma-4-31b-it:free",
  groq: "groq:openai/gpt-oss-20b",
  nvidia: "nvidia:openai/gpt-oss-20b",
};

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
/** "1 Nov" for a midnight-UTC reset, else "14 Oct 13:05 UTC". */
export function formatUntil(ms: number): string {
  const d = new Date(ms);
  const day = `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`;
  if (d.getUTCHours() === 0 && d.getUTCMinutes() === 0) return day;
  return `${day} ${String(d.getUTCHours()).padStart(2, "0")}:${String(d.getUTCMinutes()).padStart(2, "0")} UTC`;
}

export type QuotaStatus = { scope: string; provider: string; model: string | null; window: QuotaWindow; since: string; until: string; label: string };

/** Live exhausted-quota scopes for health/telemetry, e.g. "Ollama: quota exhausted until 1 Nov". */
export function quotaSnapshot(): QuotaStatus[] {
  const now = clock();
  const out: QuotaStatus[] = [];
  for (const [key, b] of [...blocks]) {
    if (expire(key, b, now)) continue;
    const name = PROVIDER_NAMES[b.provider as ProviderId] ?? b.provider;
    const model = b.scope === b.provider ? null : b.scope.slice(b.provider.length + 1);
    out.push({
      scope: b.scope,
      provider: b.provider,
      model,
      window: b.window,
      since: new Date(b.since).toISOString(),
      until: new Date(b.until).toISOString(),
      label: `${name}${model ? ` ${model}` : ""}: quota exhausted until ${formatUntil(b.until)}`,
    });
  }
  return out;
}

/** Test hook. */
export function resetQuota(): void {
  for (const b of blocks.values()) for (const m of affectedModels(b)) clearCooldown(m);
  blocks.clear();
}

// ---- persistence (best effort) ---------------------------------------------------

const KEY_PREFIX = "llm-quota|";

function persist(b: Block): void {
  if (!isDbUp()) return;
  const payload = { scope: b.scope, provider: b.provider, window: b.window, until: b.until, since: b.since, probeModel: b.probeModel };
  void db()
    .webCache.upsert({ where: { key: KEY_PREFIX + b.scope }, create: { key: KEY_PREFIX + b.scope, payload, expiresAt: new Date(b.until) }, update: { payload, expiresAt: new Date(b.until) } })
    .catch((e) => log.warn("quota persist failed", { message: (e as Error).message?.slice(0, 100) }));
}

function unpersist(scope: string): void {
  if (!isDbUp()) return;
  void db()
    .webCache.deleteMany({ where: { key: KEY_PREFIX + scope } })
    .catch(() => {});
}

let restored: Promise<void> | null = null;
/** Loads blocks saved before a restart (once per process; never throws). */
export function restoreQuota(): Promise<void> {
  restored ??= (async () => {
    if (!isDbUp()) {
      restored = null; // try again once the database is up
      return;
    }
    try {
      const rows = await db().webCache.findMany({ where: { key: { startsWith: KEY_PREFIX }, expiresAt: { gt: new Date() } } });
      for (const row of rows) {
        const p = row.payload as { scope?: string; provider?: string; window?: QuotaWindow; until?: number; since?: number; probeModel?: string };
        if (!p?.scope || !p.provider || typeof p.until !== "number" || blocks.has(p.scope)) continue;
        const window = p.window ?? "unknown";
        const now = clock();
        const b: Block = { scope: p.scope, provider: p.provider, window, until: p.until, since: p.since ?? now, nextProbeAt: now + PROBE_EVERY_MS[window], probing: false, probeModel: p.probeModel ?? PROBE_MODELS[p.provider] ?? p.scope };
        blocks.set(b.scope, b);
        for (const m of affectedModels(b)) setCooldown(m, Math.max(0, b.until - Date.now()));
        log.info("provider quota restored from db", { provider: b.provider, scope: b.scope, until: new Date(b.until).toISOString() });
      }
    } catch (e) {
      log.warn("quota restore failed", { message: (e as Error).message?.slice(0, 100) });
    }
  })();
  return restored;
}
