import { config } from "../config.js";
import { postLines } from "./http.js";
import { UpstreamError, toOpenAiMessages, type Message, type StreamHandle, type StreamOptions, type StreamUsage } from "../providers.js";

export function streamOpenRouter(model: string, messages: Message[], opts: StreamOptions): StreamHandle {
  const usage: StreamUsage = { promptTokens: null, completionTokens: null, finishReason: null };
  async function* tokens(): AsyncGenerator<string> {
    if (!config.openrouterApiKey) throw new UpstreamError(401, "OPENROUTER_API_KEY missing");
    const lines = postLines(
      "https://openrouter.ai/api/v1/chat/completions",
      { Authorization: `Bearer ${config.openrouterApiKey}`, "X-Title": "Agent Worker" },
      { model, messages: toOpenAiMessages(messages), stream: true, ...(opts.maxTokens ? { max_tokens: opts.maxTokens } : {}) },
      opts,
    );
    for await (const line of lines) {
      if (!line.startsWith("data:")) continue; // ": OPENROUTER PROCESSING" comments and blanks
      const payload = line.slice(5).trim();
      if (payload === "[DONE]") return;
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
      if (choice?.finish_reason) usage.finishReason = choice.finish_reason === "length" ? "length" : "stop";
      const text = choice?.delta?.content; // delta.reasoning is ignored
      if (typeof text === "string" && text) yield text;
    }
  }
  return { tokens: tokens(), usage };
}
