import { config } from "../config.js";
import { postLines } from "./http.js";
import { MODELS } from "../models.js";
import { OPENROUTER_VISION_FREE } from "./vision.js";
import { UpstreamError, mapFinish, toOpenAiMessages, type Message, type StreamHandle, type StreamOptions, type StreamUsage } from "../providers.js";

/** OpenRouter accepts at most this many models per request (primary + fallbacks). */
const MAX_ROUTE_MODELS = 3;
/**
 * Other free OpenRouter models to fall back to server-side when [model]'s
 * upstream is saturated: OpenRouter tries them in order within one request.
 * A request with images only falls back to other vision models.
 */
export function fallbackModels(model: string, vision = false): string[] {
  if (!model.endsWith(":free")) return [];
  const pool = vision ? OPENROUTER_VISION_FREE : MODELS.filter((m) => m.provider === "openrouter").map((m) => m.id.slice("openrouter:".length));
  return pool.filter((id) => id !== model && id.endsWith(":free")).slice(0, MAX_ROUTE_MODELS - 1);
}

/** A 429/5xx from the free model's upstream provider, not our own key's quota. */
export function isUpstreamBusy(e: unknown): boolean {
  if (!(e instanceof UpstreamError)) return false;
  if (e.status !== 429 && e.status < 500) return false;
  return !/free-models-per-day|credits|quota/i.test(e.message ?? "");
}

export function streamOpenRouter(model: string, messages: Message[], opts: StreamOptions): StreamHandle {
  const usage: StreamUsage = { promptTokens: null, completionTokens: null, finishReason: null, completed: false };
  const alternates = fallbackModels(model, messages.some((m) => (m.images?.length ?? 0) > 0));
  async function* attempt(): AsyncGenerator<string> {
    const lines = postLines(
      "https://openrouter.ai/api/v1/chat/completions",
      { Authorization: `Bearer ${opts.apiKey ?? config.openrouterApiKey}`, "X-Title": "sparky", "HTTP-Referer": config.publicBaseUrl },
      {
        model,
        ...(alternates.length ? { models: [model, ...alternates] } : {}),
        messages: toOpenAiMessages(messages),
        stream: true,
        ...(opts.maxTokens ? { max_tokens: opts.maxTokens } : {}),
        ...(opts.temperature !== undefined ? { temperature: opts.temperature } : {}),
      },
      opts,
    );
    yield* readLines(lines, usage);
  }
  async function* tokens(): AsyncGenerator<string> {
    if (!(opts.apiKey ?? config.openrouterApiKey)) throw new UpstreamError(401, "OPENROUTER_API_KEY missing");
    // No local retry on a saturated upstream: the request already carries OpenRouter's
    // server-side fallbacks, and the router moves on to the next model at once.
    yield* attempt();
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
