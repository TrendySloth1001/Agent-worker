import { clearCooldown } from "../models.js";
import { streamModel, UpstreamError, type Message } from "../providers.js";
import { recordUsage } from "../db/usage.js";
import { noteOpenRouterFreeRequest } from "../usage/openrouterKey.js";
import { applyCooldown, withSlot } from "./router.js";

export type AskOptions = {
  /** Whole-call budget, including the wait for a provider slot. */
  timeoutMs: number;
  maxTokens?: number;
  reasoningEffort?: "low";
  /** Stop collecting (and cancel the stream) once this many characters arrived. */
  maxChars?: number;
  signal?: AbortSignal;
  /** Telemetry label: table-draft, table-judge, github-review, ... */
  purpose?: string;
};

type Provider = "ollama" | "openrouter" | "groq" | "nvidia";

/**
 * One non-streamed model call: collects the text, records usage, applies
 * cooldowns on quota/auth failures and respects the provider concurrency
 * limits used by runChat. Throws UpstreamError (status 0 on timeout/empty).
 */
export async function ask(modelId: string, messages: Message[], opts: AskOptions): Promise<string> {
  const ctl = new AbortController();
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    ctl.abort();
  }, opts.timeoutMs);
  const onAbort = () => ctl.abort();
  if (opts.signal?.aborted) ctl.abort();
  opts.signal?.addEventListener("abort", onAbort, { once: true });
  const provider = modelId.slice(0, modelId.indexOf(":")) as Provider;
  const model = modelId.slice(provider.length + 1);

  try {
    return await withSlot(modelId, ctl.signal, async () => {
      const started = Date.now();
      let ttft: number | null = null;
      try {
        const left = Math.max(1_000, opts.timeoutMs);
        const handle = await streamModel(modelId, messages, { signal: ctl.signal, firstByteMs: left, idleMs: left, maxTokens: opts.maxTokens, reasoningEffort: opts.reasoningEffort });
        let text = "";
        for await (const token of handle.tokens) {
          ttft ??= Date.now() - started;
          text += token;
          if (opts.maxChars && text.length >= opts.maxChars) {
            text = text.slice(0, opts.maxChars);
            break;
          }
        }
        if (!text.trim()) throw new UpstreamError(0, "empty response");
        recordUsage({ provider, model, kind: "chat", purpose: opts.purpose, ok: true, status: 200, latencyMs: Date.now() - started, ttftMs: ttft, promptTokens: handle.usage.promptTokens, completionTokens: handle.usage.completionTokens });
        if (modelId.endsWith(":free")) noteOpenRouterFreeRequest();
        clearCooldown(modelId);
        return text;
      } catch (e) {
        const err = timedOut
          ? new UpstreamError(0, "timeout")
          : e instanceof UpstreamError
            ? e
            : opts.signal?.aborted
              ? e
              : new UpstreamError(0, (e as Error).message ?? "unknown error");
        if (err instanceof UpstreamError) {
          recordUsage({ provider, model, kind: "chat", purpose: opts.purpose, ok: false, status: err.status || undefined, latencyMs: Date.now() - started, ttftMs: ttft, errorMessage: err.message });
          applyCooldown(modelId, err);
        }
        throw err;
      }
    });
  } catch (e) {
    if (timedOut && !(e instanceof UpstreamError)) throw new UpstreamError(0, "timeout waiting for a slot");
    throw e;
  } finally {
    clearTimeout(timer);
    opts.signal?.removeEventListener("abort", onAbort);
  }
}
