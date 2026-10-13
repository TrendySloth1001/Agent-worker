import { config } from "../config.js";
import { AppError } from "../util/errors.js";
import { recordUsage } from "../db/usage.js";
import { classifyError, markQuota, quotaBlock } from "../llm/quota.js";

/** Pseudo model id for Ollama's web tools: quota blocks on the "ollama" provider cover it. */
export const OLLAMA_WEB_ID = "ollama:web_search";

async function errorDetail(res: Response): Promise<string> {
  const text = await res.text().catch(() => "");
  try {
    const j = JSON.parse(text);
    const msg = j?.error?.message ?? j?.error ?? j?.message;
    if (typeof msg === "string") return msg;
  } catch {
    /* not JSON */
  }
  return text.slice(0, 300);
}

export const clip =(s: unknown, n: number) => (typeof s === "string" ? s.slice(0, n) : "");

/** POST to Ollama's hosted web_search / web_fetch; records usage under provider "ollama". */
export async function ollamaPost(path: "web_search" | "web_fetch", body: object, signal?: AbortSignal, timeoutMs = 10_000) {
  if (!config.ollamaApiKey) throw new AppError(503, "unavailable", "Web search is not configured");
  // The Ollama account quota is shared with chat: while it is exhausted, do not call at all.
  const blocked = quotaBlock(OLLAMA_WEB_ID);
  if (blocked) throw new AppError(503, "unavailable", `Ollama quota exhausted until ${new Date(blocked.until).toISOString()}`);
  const kind = path === "web_search" ? "search" : "fetch";
  const started = Date.now();
  let status = 0;
  try {
    const res = await fetch(`https://ollama.com/api/${path}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${config.ollamaApiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(timeoutMs)]) : AbortSignal.timeout(timeoutMs),
    });
    status = res.status;
    if (!res.ok) {
      const detail = await errorDetail(res);
      const c = classifyError(OLLAMA_WEB_ID, { status: res.status, message: detail, retryAfterMs: undefined });
      if (c.kind === "quota_exhausted") markQuota(OLLAMA_WEB_ID, c, detail);
      throw new AppError(502, "upstream_failed", `${path} failed (${res.status})${detail ? `: ${detail.slice(0, 120)}` : ""}`, res.status === 429 || res.status >= 500);
    }
    const data = await res.json();
    recordUsage({ provider: "ollama", kind, ok: true, status, latencyMs: Date.now() - started });
    return data as any;
  } catch (e) {
    if (!(e instanceof AppError) || status) recordUsage({ provider: "ollama", kind, ok: false, status: status || undefined, latencyMs: Date.now() - started, errorMessage: (e as Error).message });
    if (e instanceof AppError) throw e;
    throw new AppError(502, "upstream_failed", `${path} failed: ${(e as Error).message}`, true);
  }
}

export const isRateLimit = (e: unknown) => e instanceof AppError && /\(429\)/.test(e.message);
export const statusOf = (e: unknown): number => {
  const m = e instanceof Error ? e.message.match(/\((\d{3})\)/) : null;
  return m ? Number(m[1]) : 0;
};
