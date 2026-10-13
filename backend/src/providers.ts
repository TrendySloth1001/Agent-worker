/** `images` are base64 JPEG strings (no data: prefix) attached to this message. */
export type Message = { role: "user" | "assistant" | "system"; content: string; images?: string[] };

/** Keeps at most `max` images in total (evenly spread within the newest messages that have them). */
export function capImages(messages: Message[], max: number): Message[] {
  const total = messages.reduce((n, m) => n + (m.images?.length ?? 0), 0);
  if (total <= max) return messages;
  let drop = total - max;
  return messages.map((m) => {
    if (!m.images?.length || drop <= 0) return m;
    const remove = Math.min(drop, m.images.length - (m.images.length > 1 ? 1 : 0));
    if (remove <= 0) return m;
    drop -= remove;
    const keep = m.images.length - remove;
    if (keep <= 0) return { ...m, images: undefined };
    const picked = Array.from({ length: keep }, (_, i) => m.images![Math.floor(((i + 0.5) * m.images!.length) / keep)]);
    return { ...m, images: picked };
  });
}

/** Only the newest image survives (models limited to one image per prompt). */
export function keepLatestImage(messages: Message[]): Message[] {
  const last = messages.map((m) => (m.images?.length ?? 0) > 0).lastIndexOf(true);
  if (last < 0) return messages;
  return messages.map((m, i) => (!m.images?.length ? m : i === last ? { ...m, images: m.images.slice(-1) } : { ...m, images: undefined }));
}

/** OpenAI-style chat messages: images become image_url parts. */
export function toOpenAiMessages(messages: Message[]): unknown[] {
  return messages.map((m) =>
    m.images?.length
      ? {
          role: m.role,
          content: [
            { type: "text", text: m.content },
            ...m.images.map((b64) => ({ type: "image_url", image_url: { url: `data:image/jpeg;base64,${b64}` } })),
          ],
        }
      : { role: m.role, content: m.content },
  );
}

/** Failure from an upstream model/API. status 0 = network, timeout or empty response. */
export class UpstreamError extends Error {
  constructor(
    public status: number,
    message: string,
    public retryAfterMs?: number,
  ) {
    super(message.slice(0, 200));
  }
  get retryable() {
    return this.status === 0 || this.status === 429 || this.status >= 500;
  }
}

export type StreamUsage = {
  promptTokens: number | null;
  completionTokens: number | null;
  finishReason: string | null;
  /** True once the upstream signalled the end (Ollama done, SSE [DONE] or a finish_reason). */
  completed: boolean;
};

/** Normalizes an OpenAI-style finish_reason: length and content_filter are surfaced, the rest is a normal stop. */
export function mapFinish(reason: string): "length" | "content_filter" | "stop" {
  return reason === "length" ? "length" : reason === "content_filter" ? "content_filter" : "stop";
}

/** `tokens` yields text deltas; `usage` is filled in as the stream progresses. */
export type StreamHandle = { tokens: AsyncGenerator<string>; usage: StreamUsage };

export type StreamOptions = { signal: AbortSignal; firstByteMs: number; idleMs: number; maxTokens?: number; /** gpt-oss on Groq only: "low" keeps short answers from being eaten by reasoning. */ reasoningEffort?: "low"; /** Sampling temperature (OpenAI-compatible providers); unset = provider default. */ temperature?: number; /** Quota re-probe: bypasses the exhausted-quota guard. */ probe?: boolean };

/**
 * Streams one model. A provider (or model) whose quota is known to be exhausted
 * fails at once with a QuotaBlockedError instead of costing a network round
 * trip; every upstream error is classified so a fresh quota exhaustion is
 * remembered for all callers (chat, aux calls, probes).
 */
export async function streamModel(id: string, messages: Message[], opts: StreamOptions): Promise<StreamHandle> {
  const quota = await import("./llm/quota.js");
  const budget = await import("./llm/budget.js");
  if (!opts.probe) quota.quotaGuard(id);
  // Proactive: a call that would not fit the model's minute/day budget is skipped before it costs a 429.
  const need = budget.estimateRequestTokens(messages, opts.maxTokens);
  if (!opts.probe) budget.guard(id, need);
  const reservation = budget.reserve(id, need);
  let handle: StreamHandle;
  try {
    handle = await openStream(id, messages, opts);
  } catch (e) {
    reservation.settle(0);
    throw e;
  }
  return { tokens: watchQuota(id, handle.tokens, quota, () => settleFrom(reservation, handle.usage)), usage: handle.usage };
}

/** Replaces the estimate with what the provider reported (prompt + completion), when it did. */
function settleFrom(r: { settle(n: number | null): void }, u: StreamUsage): void {
  r.settle(u.promptTokens === null && u.completionTokens === null ? null : (u.promptTokens ?? 0) + (u.completionTokens ?? 0));
}

async function* watchQuota(id: string, tokens: AsyncGenerator<string>, quota: typeof import("./llm/quota.js"), onEnd: () => void): AsyncGenerator<string> {
  try {
    yield* tokens;
  } catch (e) {
    if (e instanceof UpstreamError) {
      const c = quota.classifyError(id, e);
      if (c.kind === "quota_exhausted") quota.markQuota(id, c, e.message);
    }
    throw e;
  } finally {
    onEnd();
  }
}

/** Llama 3.2 Vision on NVIDIA accepts one image per prompt. */
const ONE_IMAGE_MODELS = /^meta\/llama-3\.2-\d+b-vision/;

async function openStream(id: string, messages: Message[], opts: StreamOptions): Promise<StreamHandle> {
  const separator = id.indexOf(":");
  const provider = id.slice(0, separator);
  const model = id.slice(separator + 1);
  if (provider === "ollama") return (await import("./llm/stream-ollama.js")).streamOllama(model, messages, opts);
  if (provider === "openrouter") return (await import("./llm/stream-openrouter.js")).streamOpenRouter(model, messages, opts);
  if (provider === "groq" || provider === "nvidia") {
    const { streamOpenAiCompatible } = await import("./llm/stream-openai.js");
    const { config } = await import("./config.js");
    const target =
      provider === "groq"
        ? { provider, url: "https://api.groq.com/openai/v1/chat/completions", apiKey: config.groqApiKey }
        : { provider, url: "https://integrate.api.nvidia.com/v1/chat/completions", apiKey: config.nvidiaApiKey };
    return streamOpenAiCompatible(target, model, provider === "groq" ? capImages(messages, 5) : ONE_IMAGE_MODELS.test(model) ? keepLatestImage(messages) : messages, opts);
  }
  throw new UpstreamError(400, `Unknown provider in ${id}`);
}

/** Non-streaming call, kept for scripts and quick checks. */
export async function complete(id: string, messages: Message[]): Promise<string> {
  const handle = await streamModel(id, messages, {
    signal: new AbortController().signal,
    firstByteMs: 30_000,
    idleMs: 30_000,
  });
  let text = "";
  for await (const token of handle.tokens) text += token;
  return text;
}
