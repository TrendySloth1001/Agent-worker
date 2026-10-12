import { MODELS, setCooldown, clearCooldown, cooldownUntil, type ModelInfo } from "../models.js";
import { streamModel, UpstreamError, type Message } from "../providers.js";
import { config } from "../config.js";
import { recordUsage } from "../db/usage.js";
import { getOpenRouterKeyInfo, noteOpenRouterFreeRequest } from "../usage/openrouterKey.js";
import { health } from "./health.js";

const FIRST_BYTE_MS = 20_000;
const IDLE_MS = 30_000;
const MAX_AUTO_ATTEMPTS = 6;

class Semaphore {
  private waiting: Array<() => void> = [];
  private free: number;
  constructor(size: number) {
    this.free = size;
  }
  get available() {
    return this.free > 0;
  }
  async acquire(signal: AbortSignal, onWait?: () => void): Promise<() => void> {
    if (this.free > 0) {
      this.free--;
      return () => this.release();
    }
    onWait?.();
    await new Promise<void>((resolve, reject) => {
      const grant = () => {
        signal.removeEventListener("abort", abort);
        resolve();
      };
      const abort = () => {
        this.waiting = this.waiting.filter((w) => w !== grant);
        reject(new DOMException("aborted", "AbortError"));
      };
      signal.addEventListener("abort", abort, { once: true });
      this.waiting.push(grant);
    });
    return () => this.release();
  }
  private release() {
    const next = this.waiting.shift();
    if (next) next();
    else this.free++;
  }
}

const semaphores = { ollama: new Semaphore(1), openrouter: new Semaphore(2), groq: new Semaphore(3), nvidia: new Semaphore(2) };

export function providerConfigured(provider: ModelInfo["provider"]) {
  const keys = { ollama: config.ollamaApiKey, openrouter: config.openrouterApiKey, groq: config.groqApiKey, nvidia: config.nvidiaApiKey };
  return !!keys[provider];
}

/** Ordered list of model ids to try. `requested` undefined/"auto" means Auto. */
export async function pickCandidates(requested?: string): Promise<string[]> {
  if (requested && requested !== "auto") return [requested];
  const { info } = await getOpenRouterKeyInfo();
  const orExhausted = info?.isFreeTier !== false && info?.remaining !== null && info?.remaining !== undefined && info.remaining <= 0;
  return MODELS.filter(
    (m) =>
      providerConfigured(m.provider) &&
      cooldownUntil(m.id) === null &&
      !(m.provider === "openrouter" && orExhausted),
  ).map((m) => m.id);
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
  if (promptChars > GROQ_MAX_PROMPT_CHARS) candidates = candidates.filter((id) => !id.startsWith("groq:"));
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

export function applyCooldown(id: string, e: UpstreamError) {
  if (e.status === 401 || e.status === 402 || e.status === 404) setCooldown(id, 3_600_000);
  else if (e.status === 429) setCooldown(id, e.retryAfterMs ?? 60_000);
  // Timeouts, stalls, empty/truncated streams (status 0) and 5xx: circuit breaker with exponential backoff.
  else if (e.status === 0 || e.status >= 500) setCooldown(id, health.failure(id));
}

/** Default output cap for chat per mode. Generous: reasoning models spend part of it thinking. */
const CHAT_MAX_TOKENS: Record<string, number> = { default: 8192, debug: 8192, review: 8192, explain: 8192, design: 12288 };
export const maxTokensForMode = (mode?: string): number => CHAT_MAX_TOKENS[mode ?? "default"] ?? 8192;

/**
 * Streams the first candidate that works. A failing candidate moves on silently
 * if it produced nothing; if it already produced text, Auto resets and moves
 * on, an explicit model fails.
 */
export async function runChat(candidates: string[], messages: Message[], signal: AbortSignal, hooks: RunHooks, auto: boolean, opts: { maxTokens?: number } = {}): Promise<RunResult> {
  const queue = [...candidates];
  const deferred = new Set<string>();
  let attempt = 0;
  let lastError: UpstreamError | null = null;
  let tried = 0;

  if (queue.length === 0) throw new ChatFailure("all_models_failed", "No model is available right now. Try again in a minute.", true);

  while (queue.length > 0) {
    if (signal.aborted) throw new DOMException("aborted", "AbortError");
    const id = queue.shift()!;
    const provider = id.slice(0, id.indexOf(":")) as ModelInfo["provider"];
    const sem = semaphores[provider];

    // In Auto, a model whose circuit opened meanwhile (another request) is dead: skip it while others remain.
    if (auto && queue.length > 0 && cooldownUntil(id) !== null) continue;

    // In Auto, prefer a provider that is free right now over waiting in line.
    if (auto && !sem.available && !deferred.has(id) && queue.length > 0) {
      deferred.add(id);
      queue.push(id);
      continue;
    }
    if (auto && tried >= MAX_AUTO_ATTEMPTS) break;
    tried++;

    const release = await sem.acquire(signal, hooks.onQueued);
    attempt++;
    const started = Date.now();
    let produced = false;
    let ttft: number | null = null;
    let handle: Awaited<ReturnType<typeof streamModel>> | null = null;
    try {
      handle = await streamModel(id, messages, { signal, firstByteMs: FIRST_BYTE_MS, idleMs: IDLE_MS, maxTokens: opts.maxTokens });
      for await (const token of handle.tokens) {
        if (!produced) {
          produced = true;
          ttft = Date.now() - started;
          hooks.onModel(id, attempt);
        }
        hooks.onDelta(token);
      }
      const completed = handle.usage.completed;
      // Nothing was sent to the client yet, so a stream that never signalled completion can still fall back.
      if (!produced) throw new UpstreamError(0, completed ? "empty response" : "stream ended without completion");
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
      const err = e instanceof UpstreamError ? e : new UpstreamError(0, (e as Error).message ?? "unknown error");
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
      applyCooldown(id, err);
      console.warn(`[chat] ${id} failed: ${describe(err)}`);

      if (!auto) {
        const busy = err.retryable;
        throw new ChatFailure(busy ? "model_busy" : "upstream_failed", busy ? "This model is busy. Try another or use Auto." : `Model rejected the request: ${describe(err)}`, busy);
      }
      if (produced) hooks.onReset();
      const next = queue[0];
      if (next) hooks.onFallback(id, next);
    } finally {
      release();
    }
  }

  throw new ChatFailure("all_models_failed", lastError ? `All models failed. Last error: ${describe(lastError)}` : "All models failed.", true);
}

/** Runs `fn` while holding the model's provider concurrency slot (shared with runChat). */
export async function withSlot<T>(id: string, signal: AbortSignal, fn: () => Promise<T>): Promise<T> {
  const provider = id.slice(0, id.indexOf(":")) as ModelInfo["provider"];
  const sem = semaphores[provider];
  if (!sem) return fn();
  const release = await sem.acquire(signal);
  try {
    return await fn();
  } finally {
    release();
  }
}
