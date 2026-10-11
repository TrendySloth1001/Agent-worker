import { streamModel, type Message } from "../providers.js";
import { recordUsage } from "../db/usage.js";

/** One non-streaming completion from a single model, with usage recorded. Throws on failure or timeout. */
export async function ask(model: string, messages: Message[], timeoutMs: number): Promise<string> {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs);
  const started = Date.now();
  const provider = model.slice(0, model.indexOf(":")) as "ollama" | "openrouter" | "groq" | "nvidia";
  try {
    const handle = await streamModel(model, messages, { signal: ctl.signal, firstByteMs: timeoutMs, idleMs: timeoutMs });
    let text = "";
    for await (const token of handle.tokens) text += token;
    recordUsage({ provider, model, kind: "chat", ok: true, latencyMs: Date.now() - started });
    return text;
  } catch (e) {
    recordUsage({ provider, model, kind: "chat", ok: false, latencyMs: Date.now() - started });
    throw e;
  } finally {
    clearTimeout(timer);
  }
}
