import { postLines } from "./http.js";
import { recordRateHeaders } from "../usage/rateLimits.js";
import { UpstreamError, toOpenAiMessages, type Message, type StreamHandle, type StreamOptions, type StreamUsage } from "../providers.js";

export type OpenAiCompatible = { provider: string; url: string; apiKey: string | undefined };

/** Streams from any OpenAI-compatible chat endpoint (Groq, NVIDIA). Reasoning deltas are ignored. */
export function streamOpenAiCompatible(target: OpenAiCompatible, model: string, messages: Message[], opts: StreamOptions): StreamHandle {
  const usage: StreamUsage = { promptTokens: null, completionTokens: null, finishReason: null };
  async function* tokens(): AsyncGenerator<string> {
    if (!target.apiKey) throw new UpstreamError(401, `${target.provider} API key missing`);
    const lines = postLines(
      target.url,
      { Authorization: `Bearer ${target.apiKey}` },
      { model, messages: toOpenAiMessages(messages), stream: true, stream_options: { include_usage: true }, ...(opts.maxTokens ? { max_tokens: opts.maxTokens } : {}) },
      { ...opts, onResponse: (res) => recordRateHeaders(`${target.provider}:${model}`, res.headers) },
    );
    for await (const line of lines) {
      if (!line.startsWith("data:")) continue;
      const payload = line.slice(5).trim();
      if (payload === "[DONE]") return;
      let data: any;
      try {
        data = JSON.parse(payload);
      } catch {
        continue;
      }
      if (data.error) {
        const code = Number(data.error.code ?? data.error.status);
        throw new UpstreamError(Number.isFinite(code) && code >= 400 ? code : 502, String(data.error.message ?? "upstream error"));
      }
      const u = data.usage ?? data.x_groq?.usage;
      if (u) {
        usage.promptTokens = u.prompt_tokens ?? null;
        usage.completionTokens = u.completion_tokens ?? null;
      }
      const choice = data.choices?.[0];
      if (choice?.finish_reason) usage.finishReason = choice.finish_reason === "length" ? "length" : "stop";
      const text = choice?.delta?.content;
      if (typeof text === "string" && text) yield text;
    }
  }
  return { tokens: tokens(), usage };
}
