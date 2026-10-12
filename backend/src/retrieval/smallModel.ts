import { recordUsage } from "../db/usage.js";
import { streamModel, UpstreamError, type Message } from "../providers.js";

/** Cheap, fast models for query rewriting and reranking. First one that answers wins. */
export const SMALL_MODELS = ["groq:openai/gpt-oss-20b", "ollama:gpt-oss:20b"];

/** One short completion under a hard deadline. Throws on timeout or upstream failure. */
export async function askSmall(model: string, messages: Message[], purpose: string, timeoutMs: number): Promise<string> {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs);
  const started = Date.now();
  const provider = model.slice(0, model.indexOf(":"));
  const name = model.slice(provider.length + 1);
  let ttft: number | null = null;
  try {
    const handle = await streamModel(model, messages, { signal: ctl.signal, firstByteMs: timeoutMs, idleMs: timeoutMs });
    let text = "";
    for await (const t of handle.tokens) {
      ttft ??= Date.now() - started;
      text += t;
    }
    recordUsage({
      provider: provider as "groq" | "ollama",
      model: name,
      kind: "chat",
      purpose,
      ok: true,
      status: 200,
      latencyMs: Date.now() - started,
      ttftMs: ttft,
      promptTokens: handle.usage.promptTokens,
      completionTokens: handle.usage.completionTokens,
    });
    return text;
  } catch (e) {
    recordUsage({
      provider: provider as "groq" | "ollama",
      model: name,
      kind: "chat",
      purpose,
      ok: false,
      status: e instanceof UpstreamError ? e.status || undefined : undefined,
      latencyMs: Date.now() - started,
      ttftMs: ttft,
      errorMessage: ctl.signal.aborted ? "timeout" : (e as Error).message,
    });
    throw e;
  } finally {
    clearTimeout(timer);
  }
}

export function extractJson(raw: string, open: "{" | "["): unknown {
  const close = open === "{" ? "}" : "]";
  const s = raw.indexOf(open);
  const e = raw.lastIndexOf(close);
  if (s < 0 || e <= s) throw new Error("no JSON in reply");
  return JSON.parse(raw.slice(s, e + 1));
}
