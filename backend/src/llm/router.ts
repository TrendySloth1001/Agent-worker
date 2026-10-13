import { MODELS, setCooldown, clearCooldown, cooldownUntil, type ModelInfo } from "../models.js";
import { streamModel, UpstreamError, type Message } from "../providers.js";
import { config } from "../config.js";
import { recordUsage, withTelemetry } from "../db/usage.js";
import { getOpenRouterKeyInfo, noteOpenRouterFreeRequest } from "../usage/openrouterKey.js";
import { BudgetBlockedError, check as budgetCheck, estimateRequestTokens, noteAuxDeferred, noteWait, sleep } from "./budget.js";
import { slots, type Priority } from "./slots.js";
import { health } from "./health.js";
import { classifyError, clearQuota, formatUntil, isQuotaBlocked, markQuota, PROVIDER_NAMES, quotaBlock, QuotaBlockedError, restoreQuota, setQuotaProber, type ErrorClass } from "./quota.js";
import { VISION_MODELS } from "./vision.js";
import { ThinkFilter } from "./think.js";
import { log } from "../util/logger.js";
import { USER_MSG } from "../util/userMessages.js";

const FIRST_BYTE_MS = 20_000;
const IDLE_MS = 30_000;
const MAX_AUTO_ATTEMPTS = 6;
/** The longest a turn waits for a minute window to free up rather than failing. */
export const BUDGET_WAIT_MAX_MS = 4_000;


export function providerConfigured(provider: ModelInfo["provider"]) {
  const keys = { ollama: config.ollamaApiKey, openrouter: config.openrouterApiKey, groq: config.groqApiKey, nvidia: config.nvidiaApiKey };
  return !!keys[provider];
}

async function openRouterExhausted(): Promise<boolean> {
  const { info } = await getOpenRouterKeyInfo();
  return info?.isFreeTier !== false && info?.remaining !== null && info?.remaining !== undefined && info.remaining <= 0;
}

const providerOf = (id: string) => id.slice(0, id.indexOf(":")) as ModelInfo["provider"];

/**
 * Models that may be called at all: provider configured, quota not exhausted
 * (hard limits). Soft cooldowns (rate limits, breaker) are applied by [healthyFirst].
 */
function usable(ids: string[], orExhausted: boolean): string[] {
  return ids.filter((id) => providerConfigured(providerOf(id)) && !isQuotaBlocked(id) && !(providerOf(id) === "openrouter" && orExhausted));
}

/**
 * The models outside any cooldown; when every usable model is cooling down
 * (rate-limit windows, breaker backoff), all of them, soonest-recovering
 * first, so Auto never ends up with nothing to try while a provider has quota.
 */
export function healthyFirst(ids: string[]): string[] {
  const healthy = ids.filter((id) => cooldownUntil(id) === null);
  if (healthy.length > 0 || ids.length === 0) return healthy;
  log.warn("no healthy model, trying the soonest-recovering ones", { models: ids.length });
  return [...ids].sort((a, b) => (cooldownUntil(a) ?? 0) - (cooldownUntil(b) ?? 0));
}

/** Ordered list of model ids to try. `requested` undefined/"auto" means Auto. */
export async function pickCandidates(requested?: string): Promise<string[]> {
  await restoreQuota();
  if (requested && requested !== "auto") return [requested];
  return healthyFirst(usable(MODELS.map((m) => m.id), await openRouterExhausted()));
}

/** Auto for a turn with images or video frames: the vision models, healthiest first. */
export async function pickVisionCandidates(): Promise<string[]> {
  await restoreQuota();
  return healthyFirst(usable(VISION_MODELS, await openRouterExhausted()));
}

/**
 * Text-only fallback for a vision turn when no vision model could answer:
 * every usable text model, healthy first.
 */
export async function pickTextFallback(): Promise<string[]> {
  return pickCandidates(undefined);
}

const LONG_CONTEXT_CHARS = 40_000;
// Groq's free tier allows 8k tokens per minute, so big prompts skip it.
const GROQ_MAX_PROMPT_CHARS = 20_000;
const LONG_CONTEXT_MODELS = new Set([
  "nvidia:nvidia/nemotron-3-ultra-550b-a55b",
  "openrouter:nvidia/nemotron-3-ultra-550b-a55b:free",
  "ollama:nemotron-3-ultra",
]);

/** Auto: move the 1M-context models to the front when the prompt is very long. */
export function preferForPrompt(candidates: string[], promptChars: number): string[] {
  // Soft preferences only: a filter that would leave nothing to try is not applied.
  if (promptChars > GROQ_MAX_PROMPT_CHARS) {
    const rest = candidates.filter((id) => !id.startsWith("groq:"));
    candidates = rest.length > 0 ? rest : candidates;
  }
  // Skip models whose minute/day budget can't fit this prompt right now (headers + local accounting).
  const need = Math.ceil(promptChars / 3.5) + 1_500;
  const fits = candidates.filter((id) => budgetCheck(id, need).ok);
  if (fits.length > 0) candidates = fits;
  if (promptChars < LONG_CONTEXT_CHARS) return candidates;
  return [...candidates.filter((id) => LONG_CONTEXT_MODELS.has(id)), ...candidates.filter((id) => !LONG_CONTEXT_MODELS.has(id))];
}

export type RunHooks = {
  onQueued(): void;
  onModel(model: string, attempt: number): void;
  onDelta(text: string): void;
  onReset(): void;
  onFallback(from: string, to: string): void;
};

export type RunResult = {
  model: string;
  promptTokens: number | null;
  completionTokens: number | null;
  finishReason: string;
};

export class ChatFailure extends Error {
  constructor(
    public code: "all_models_failed" | "model_busy" | "upstream_failed" | "unavailable",
    message: string,
    public retryable: boolean,
  ) {
    super(message);
  }
}

function describe(e: UpstreamError): string {
  if (e.status === 0) return e.message;
  return `${e.status} ${e.message}`.slice(0, 200);
}

/**
 * Cools a failed model down according to what went wrong (see quota.ts):
 * an exhausted quota blocks its provider (or model) until the window resets,
 * a rate limit honours Retry-After, a saturated free upstream gets a short
 * pause, auth/unknown-model an hour, and timeouts/5xx the growing breaker backoff.
 */
export function applyCooldown(id: string, e: UpstreamError): ErrorClass {
  const c = classifyError(id, e);
  switch (c.kind) {
    case "quota_exhausted":
      markQuota(id, c, e.message);
      break;
    case "rate_limited":
    case "upstream_busy":
    case "auth":
      setCooldown(id, c.cooldownMs);
      break;
    case "transient":
      setCooldown(id, health.failure(id));
      break;
  }
  return c;
}

/** What the user reads when Auto ran out of models. The code stays all_models_failed. */
export const ALL_BUSY_MESSAGE = USER_MSG.busy;
export const ALL_QUOTA_MESSAGE = USER_MSG.allQuota;

/** A picked model whose allowance ran out (the provider and reset time go to the logs only). */
function quotaMessage(id: string, until: number): string {
  log.info("picked model out of quota", { model: id, provider: PROVIDER_NAMES[providerOf(id)] ?? providerOf(id), until: formatUntil(until) });
  return USER_MSG.modelQuota;
}

/** Default output cap for chat per mode. Generous: reasoning models spend part of it thinking. */
const CHAT_MAX_TOKENS: Record<string, number> = { default: 8192, debug: 8192, review: 8192, explain: 8192, design: 12288 };
export const maxTokensForMode = (mode?: string): number => CHAT_MAX_TOKENS[mode ?? "default"] ?? 8192;

const CHITCHAT_MAX_TOKENS = 1536;
const CONCISE_MAX_TOKENS = 4096;

/**
 * The reply cap for a turn: the mode's cap, lowered for small talk (a few
 * sentences) and for a "concise" profile. The cap counts against Groq's
 * per-minute token window, so a tight one keeps the window free for other turns.
 */
export function maxTokensFor(o: { mode?: string; intent?: { top: string; confidence: number; uncertain: boolean }; length?: string }): number {
  const base = maxTokensForMode(o.mode);
  if (o.intent && !o.intent.uncertain && o.intent.confidence >= 0.6 && o.intent.top === "chitchat") return Math.min(base, CHITCHAT_MAX_TOKENS);
  if (o.length === "concise" && (o.mode ?? "default") === "default") return Math.min(base, CONCISE_MAX_TOKENS);
  return base;
}

/** Small, fast models that answer small talk as well as the big ones. */
const SMALL_CHAT_MODELS = ["groq:openai/gpt-oss-20b", "nvidia:nvidia/nemotron-3.5-lightning-30b-a3b", "nvidia:openai/gpt-oss-20b", "ollama:gpt-oss:20b"];

/** Auto for a trivial turn: the small models first (they keep the big models' rate-limit windows free), the rest after. */
export function preferSmall(candidates: string[]): string[] {
  const small = SMALL_CHAT_MODELS.filter((id) => candidates.includes(id));
  return small.length ? [...small, ...candidates.filter((id) => !small.includes(id))] : candidates;
}

/**
 * Streams the first candidate that works. A failing candidate moves on silently
 * if it produced nothing; if it already produced text, Auto resets and moves
 * on, an explicit model fails.
 */
export async function runChat(
  candidates: string[],
  messages: Message[],
  signal: AbortSignal,
  hooks: RunHooks,
  auto: boolean,
  opts: {
    maxTokens?: number;
    /** Auto: a model with no visible text after this long is abandoned for the next candidate (the last one always gets to finish). */
    firstTokenMs?: number;
    /** Test hook. */ stream?: typeof streamModel;
  } = {},
): Promise<RunResult> {
  const stream = opts.stream ?? streamModel;
  // Auto never calls a model whose quota is known to be exhausted.
  const queue = auto ? candidates.filter((id) => !isQuotaBlocked(id)) : [...candidates];
  const deferred = new Set<string>();
  let attempt = 0;
  let lastError: UpstreamError | null = null;
  let tried = 0;

  if (queue.length === 0) {
    const anyQuota = candidates.length > 0;
    throw new ChatFailure("all_models_failed", anyQuota ? ALL_QUOTA_MESSAGE : ALL_BUSY_MESSAGE, true);
  }
  if (!auto) {
    const blocked = quotaBlock(queue[0]);
    if (blocked) throw new ChatFailure("model_busy", quotaMessage(queue[0], blocked.until), true);
  }

  // Budgets: Auto tries the models that fit their minute/day windows first. When none fits (or the
  // one picked model doesn't) but a window frees within a few seconds, wait briefly instead of failing.
  const need = estimateRequestTokens(messages, opts.maxTokens);
  const verdicts = new Map(queue.map((id) => [id, budgetCheck(id, need)] as const));
  const fitting = queue.filter((id) => verdicts.get(id)!.ok);
  if (auto && fitting.length > 0 && fitting.length < queue.length) {
    const rest = queue.filter((id) => !verdicts.get(id)!.ok);
    queue.splice(0, queue.length, ...fitting, ...rest);
  }
  const considered = auto ? queue : queue.slice(0, 1);
  if (considered.length > 0 && considered.every((id) => !verdicts.get(id)!.ok)) {
    const waitMs = Math.min(...considered.map((id) => { const v = verdicts.get(id)!; return v.ok ? 0 : v.waitMs; }));
    if (waitMs <= BUDGET_WAIT_MAX_MS) {
      hooks.onQueued();
      noteWait(waitMs);
      await sleep(waitMs + 50, signal);
    }
  }

  while (queue.length > 0) {
    if (signal.aborted) throw new DOMException("aborted", "AbortError");
    const id = queue.shift()!;
    const provider = providerOf(id);
    const sem = slots[provider];

    // In Auto, a model whose quota ran out or whose circuit opened meanwhile (another request) is skipped
    // while a healthy one remains; when all are cooling down they are tried in order rather than giving up.
    if (auto && isQuotaBlocked(id)) continue;
    if (auto && cooldownUntil(id) !== null && queue.some((q) => cooldownUntil(q) === null && !isQuotaBlocked(q))) continue;

    // In Auto, prefer a provider that is free right now over waiting in line.
    if (auto && sem && !sem.available && !deferred.has(id) && queue.length > 0) {
      deferred.add(id);
      queue.push(id);
      continue;
    }
    if (auto && tried >= MAX_AUTO_ATTEMPTS) break;
    tried++;

    const release = sem ? await sem.acquire(signal, { onWait: hooks.onQueued }) : () => {};
    attempt++;
    const started = Date.now();
    let produced = false;
    let ttft: number | null = null;
    let handle: Awaited<ReturnType<typeof streamModel>> | null = null;
    // Slow first token (e.g. a reasoning model thinking for 30 s): give way to the next model while one remains.
    const attemptCtl = new AbortController();
    const onOuterAbort = () => attemptCtl.abort();
    signal.addEventListener("abort", onOuterAbort, { once: true });
    let slowFirstToken = false;
    const firstTokenTimer = auto && opts.firstTokenMs && queue.some((q) => !isQuotaBlocked(q))
      ? setTimeout(() => {
          if (produced) return;
          slowFirstToken = true;
          attemptCtl.abort();
        }, opts.firstTokenMs)
      : null;
    const think = new ThinkFilter();
    const emit = (visible: string) => {
      if (!visible) return;
      if (!produced) {
        // Only visible text counts: a reply that is all <think> (or whitespace) falls back to the next model.
        if (!visible.trim()) return;
        produced = true;
        ttft = Date.now() - started;
        if (firstTokenTimer) clearTimeout(firstTokenTimer);
        hooks.onModel(id, attempt);
      }
      hooks.onDelta(visible);
    };
    try {
      handle = await stream(id, messages, { signal: attemptCtl.signal, firstByteMs: FIRST_BYTE_MS, idleMs: IDLE_MS, maxTokens: opts.maxTokens });
      for await (const token of handle.tokens) emit(think.push(token));
      emit(think.flush());
      const completed = handle.usage.completed;
      // Nothing was sent to the client yet, so a stream that never signalled completion can still fall back.
      if (!produced) throw new UpstreamError(0, completed ? "empty response (no visible text)" : "stream ended without completion");
      recordUsage({
        provider,
        model: id.slice(provider.length + 1),
        kind: "chat",
        ok: true,
        status: 200,
        latencyMs: Date.now() - started,
        ttftMs: ttft,
        attempt,
        promptTokens: handle.usage.promptTokens,
        completionTokens: handle.usage.completionTokens,
      });
      if (id.endsWith(":free")) noteOpenRouterFreeRequest();
      clearQuota(id);
      let finishReason = handle.usage.finishReason ?? "stop";
      if (completed) {
        clearCooldown(id);
        health.success(id);
      } else {
        // Text already reached the client: keep it, flag the cut-off, and count it against the model.
        finishReason = "interrupted";
        setCooldown(id, health.failure(id));
        console.warn(`[chat] ${id} stream ended without completion`);
      }
      return {
        model: id,
        promptTokens: handle.usage.promptTokens,
        completionTokens: handle.usage.completionTokens,
        finishReason,
      };
    } catch (e) {
      if (signal.aborted) throw e;
      if (slowFirstToken) {
        // Not a health problem, just slow: no cooldown, try the next model.
        lastError = new UpstreamError(0, "slow first token");
        recordUsage({ provider, model: id.slice(provider.length + 1), kind: "chat", ok: false, latencyMs: Date.now() - started, attempt, errorMessage: "slow first token" });
        console.warn(`[chat] ${id} gave no visible text within ${opts.firstTokenMs} ms, trying the next model`);
        const next = queue.find((q) => !isQuotaBlocked(q));
        if (next) hooks.onFallback(id, next);
        continue;
      }
      const err = e instanceof UpstreamError ? e : new UpstreamError(0, (e as Error).message ?? "unknown error");
      // A quota block found at call time (another request just hit it) costs nothing: no usage row, no cooldown.
      const skipped = err instanceof QuotaBlockedError;
      if (!skipped) {
        lastError = err;
        recordUsage({
          provider,
          model: id.slice(provider.length + 1),
          kind: "chat",
          ok: false,
          status: err.status || undefined,
          latencyMs: Date.now() - started,
          ttftMs: ttft,
          attempt,
          errorMessage: err.message,
          promptTokens: handle?.usage.promptTokens ?? null,
          completionTokens: handle?.usage.completionTokens ?? null,
        });
      } else {
        attempt--;
        tried--;
      }
      const cls = applyCooldown(id, err);
      if (!skipped) console.warn(`[chat] ${id} failed (${cls.kind}): ${describe(err)}`);

      if (!auto) {
        const blocked = quotaBlock(id);
        if (blocked) throw new ChatFailure("model_busy", quotaMessage(id, blocked.until), true);
        const busy = err.retryable;
        throw new ChatFailure(busy ? "model_busy" : "upstream_failed", busy ? USER_MSG.modelBusy : USER_MSG.modelRejected, busy);
      }
      if (produced) hooks.onReset();
      const next = queue.find((q) => !isQuotaBlocked(q));
      if (next && !skipped) hooks.onFallback(id, next);
    } finally {
      if (firstTokenTimer) clearTimeout(firstTokenTimer);
      signal.removeEventListener("abort", onOuterAbort);
      release();
    }
  }

  if (lastError) console.warn(`[chat] all models failed, last error: ${describe(lastError)}`);
  const allQuota = candidates.length > 0 && candidates.every((id) => isQuotaBlocked(id));
  throw new ChatFailure("all_models_failed", allQuota ? ALL_QUOTA_MESSAGE : ALL_BUSY_MESSAGE, true);
}

/** How long an aux call may wait for a spare provider slot before it is skipped. */
export const AUX_SLOT_WAIT_MS = 1_500;

/**
 * Runs `fn` while holding the model's provider concurrency slot (shared with runChat).
 * Aux work only takes a spare slot (never the last one) and is skipped after a short wait.
 */
export async function withSlot<T>(id: string, signal: AbortSignal, fn: () => Promise<T>, o: { priority?: Priority; purpose?: string } = {}): Promise<T> {
  const provider = id.slice(0, id.indexOf(":")) as ModelInfo["provider"];
  const sem = slots[provider];
  if (!sem) return fn();
  let release: () => void;
  try {
    release = await sem.acquire(signal, o.priority === "aux" ? { priority: "aux", maxWaitMs: AUX_SLOT_WAIT_MS } : {});
  } catch (e) {
    if ((e as Error).message !== "slot_busy") throw e;
    noteAuxDeferred(o.purpose ?? "aux");
    throw new BudgetBlockedError(id, "aux_deferred", AUX_SLOT_WAIT_MS);
  }
  try {
    return await fn();
  } finally {
    release();
  }
}

/**
 * Re-probe of an exhausted quota: one tiny request (a few tokens, bypassing the
 * quota guard). Resolves when the provider answers, rejects with its error.
 */
// Probes run in the background of whichever request noticed them: keep them out of that turn's counters.
setQuotaProber((id) => withTelemetry({ purpose: "quota-probe", turn: undefined }, () => probeQuota(id)));

async function probeQuota(id: string): Promise<void> {
  const provider = providerOf(id);
  const started = Date.now();
  try {
    const handle = await streamModel(id, [{ role: "user", content: "Reply with: ok" }], { signal: AbortSignal.timeout(20_000), firstByteMs: 15_000, idleMs: 15_000, maxTokens: 8, probe: true });
    for await (const _ of handle.tokens) break;
    recordUsage({ provider, model: id.slice(provider.length + 1), kind: "chat", purpose: "quota-probe", ok: true, status: 200, latencyMs: Date.now() - started });
  } catch (e) {
    const err = e instanceof UpstreamError ? e : new UpstreamError(0, (e as Error).message ?? "probe failed");
    recordUsage({ provider, model: id.slice(provider.length + 1), kind: "chat", purpose: "quota-probe", ok: false, status: err.status || undefined, latencyMs: Date.now() - started, errorMessage: err.message });
    throw err;
  }
}
