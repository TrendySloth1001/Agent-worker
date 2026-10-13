import { streamModel, UpstreamError, type Message } from "../providers.js";
import { recordUsage } from "../db/usage.js";
import { auxGate, auxOnce, isAux } from "../llm/aux.js";
import { estimateRequestTokens } from "../llm/budget.js";
import { withSlot } from "../llm/router.js";

/** One non-streaming completion from a single model, with usage recorded. Throws on failure or timeout. */
export async function ask(model: string, messages: Message[], timeoutMs: number, purpose?: string): Promise<string> {
  if (!isAux(purpose)) return askOnce(model, messages, timeoutMs, purpose);
  // Titles, memory and summaries are aux work: skipped while budgets are tight, shared when identical.
  auxGate(model, estimateRequestTokens(messages), purpose!);
  return auxOnce(purpose!, messages, () => withSlot(model, AbortSignal.timeout(timeoutMs), () => askOnce(model, messages, timeoutMs, purpose), { priority: "aux", purpose }));
}

async function askOnce(model: string, messages: Message[], timeoutMs: number, purpose?: string): Promise<string> {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs);
  const started = Date.now();
  const provider = model.slice(0, model.indexOf(":")) as "ollama" | "openrouter" | "groq" | "nvidia";
  const name = model.slice(provider.length + 1);
  let ttft: number | null = null;
  let handle: Awaited<ReturnType<typeof streamModel>> | null = null;
  try {
    handle = await streamModel(model, messages, { signal: ctl.signal, firstByteMs: timeoutMs, idleMs: timeoutMs });
    let text = "";
    for await (const token of handle.tokens) {
      ttft ??= Date.now() - started;
      text += token;
    }
    recordUsage({ provider, model: name, kind: "chat", purpose, ok: true, status: 200, latencyMs: Date.now() - started, ttftMs: ttft, promptTokens: handle.usage.promptTokens, completionTokens: handle.usage.completionTokens });
    return text;
  } catch (e) {
    const status = e instanceof UpstreamError ? e.status || undefined : undefined;
    const message = ctl.signal.aborted ? "timeout" : (e as Error).message;
    recordUsage({ provider, model: name, kind: "chat", purpose, ok: false, status, latencyMs: Date.now() - started, ttftMs: ttft, errorMessage: message, promptTokens: handle?.usage.promptTokens ?? null, completionTokens: handle?.usage.completionTokens ?? null });
    throw e;
  } finally {
    clearTimeout(timer);
  }
}
