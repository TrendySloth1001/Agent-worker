import { config } from "../config.js";
import { postLines } from "./http.js";
import { UpstreamError, type Message, type StreamHandle, type StreamOptions, type StreamUsage } from "../providers.js";

export function streamOllama(model: string, messages: Message[], opts: StreamOptions): StreamHandle {
  const usage: StreamUsage = { promptTokens: null, completionTokens: null, finishReason: null, completed: false };
  async function* tokens(): AsyncGenerator<string> {
    if (!config.ollamaApiKey) throw new UpstreamError(401, "OLLAMA_API_KEY missing");
    const lines = postLines(
      "https://ollama.com/api/chat",
      { Authorization: `Bearer ${config.ollamaApiKey}` },
      { model, messages: messages.map((m) => (m.images?.length ? { role: m.role, content: m.content, images: m.images } : { role: m.role, content: m.content })), stream: true, ...(opts.maxTokens ? { options: { num_predict: opts.maxTokens } } : {}) },
      opts,
    );
    for await (const line of lines) {
      if (!line.trim()) continue;
      let data: any;
      try {
        data = JSON.parse(line);
      } catch {
        continue;
      }
      if (data.error) throw new UpstreamError(typeof data.status_code === "number" ? data.status_code : 502, String(data.error));
      const text = data.message?.content;
      if (typeof text === "string" && text) yield text; // message.thinking is ignored
      if (data.done) {
        usage.promptTokens = data.prompt_eval_count ?? null;
        usage.completionTokens = data.eval_count ?? null;
        usage.finishReason = data.done_reason ?? "stop";
        usage.completed = true;
        return;
      }
    }
  }
  return { tokens: tokens(), usage };
}
