import { config } from "../config.js";
import { postLines } from "./http.js";
import { MODELS } from "../models.js";
import { UpstreamError, mapFinish, toOpenAiMessages, type Message, type StreamHandle, type StreamOptions, type StreamUsage } from "../providers.js";

/** OpenRouter accepts at most this many models per request (primary + fallbacks). */
const MAX_ROUTE_MODELS = 3;
/** Free upstreams are often briefly saturated ("Provider returned error"); one quick retry usually lands. */
const UPSTREAM_RETRY_MS = 1_200;

/**
 * Other free OpenRouter models to fall back to server-side when [model]'s
 * upstream is saturated: OpenRouter tries them in order within one request.
 */
export function fallbackModels(model: string): string[] {
  if (!model.endsWith(":free")) return [];
  return MODELS.filter((m) => m.provider === "openrouter" && m.id !== `openrouter:${model}`)
    .map((m) => m.id.slice("openrouter:".length))
    .filter((id) => id.endsWith(":free"))
    .slice(0, MAX_ROUTE_MODELS - 1);
}

/** A 429/5xx from the free model's upstream provider, not our own key's quota. */
export function isUpstreamBusy(e: unknown): boolean {
  if (!(e instanceof UpstreamError)) return false;
  if (e.status !== 429 && e.status < 500) return false;
  return !/free-models-per-day|credits|quota/i.test(e.message ?? "");
}

export function streamOpenRouter(model: string, messages: Message[], opts: StreamOptions): StreamHandle {
  const usage: StreamUsage = { promptTokens: null, completionTokens: null, finishReason: null, completed: false };
  const alternates = fallbackModels(model);
  async function* attempt(): AsyncGenerator<string> {
    const lines = postLines(
      "https://openrouter.ai/api/v1/chat/completions",
      { Authorization: `Bearer ${config.openrouterApiKey}`, "X-Title": "sparky", "HTTP-Referer": config.publicBaseUrl },
      {
        model,
        ...(alternates.length ? { models: [model, ...alternates] } : {}),
        messages: toOpenAiMessages(messages),
        stream: true,
        ...(opts.maxTokens ? { max_tokens: opts.maxTokens } : {}),
      },
      opts,
    );
    yield* readLines(lines, usage);
  }
  async function* tokens(): AsyncGenerator<string> {
    if (!config.openrouterApiKey) throw new UpstreamError(401, "OPENROUTER_API_KEY missing");
    let sent = false;
    try {
      for await (const t of attempt()) {
        sent = true;
        yield t;
      }
    } catch (e) {
      // Retry once only if nothing reached the caller yet.
      if (sent || !isUpstreamBusy(e) || opts.signal?.aborted) throw e;
      await new Promise((r) => setTimeout(r, UPSTREAM_RETRY_MS));
      yield* attempt();
    }
  }
  return { tokens: tokens(), usage };
}

async function* readLines(lines: AsyncIterable<string>, usage: StreamUsage): AsyncGenerator<string> {
  for await (const line of lines) {
    if (!line.startsWith("data:")) continue; // ": OPENROUTER PROCESSING" comments and blanks
    const payload = line.slice(5).trim();
    if (payload === "[DONE]") {
      usage.completed = true;
      return;
    }
    let data: any;
    try {
      data = JSON.parse(payload);
    } catch {
      continue;
    }
    if (data.error) {
      const code = Number(data.error.code);
      throw new UpstreamError(Number.isFinite(code) && code >= 400 ? code : 502, String(data.error.message ?? "upstream error"));
    }
    if (data.usage) {
      usage.promptTokens = data.usage.prompt_tokens ?? null;
      usage.completionTokens = data.usage.completion_tokens ?? null;
    }
    const choice = data.choices?.[0];
    if (choice?.finish_reason) {
      usage.finishReason = mapFinish(choice.finish_reason);
      usage.completed = true;
    }
    const text = choice?.delta?.content; // delta.reasoning is ignored
    if (typeof text === "string" && text) yield text;
  }
}
