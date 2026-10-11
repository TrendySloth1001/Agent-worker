import { config } from "../config.js";
import { getEmbeddingGuardError } from "../db/embeddingGuard.js";
import { recordUsage } from "../db/usage.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";

const ENDPOINTS = {
  nvidia: { url: "https://integrate.api.nvidia.com/v1/embeddings", key: () => config.nvidiaApiKey },
  openrouter: { url: "https://openrouter.ai/api/v1/embeddings", key: () => config.openrouterApiKey },
} as const;

const endpoint = () => ENDPOINTS[config.embeddingProvider];
const MAX_TRIES = 5;
const MAX_CHARS = 8000;

let lastFailAt = 0;
let lastOkAt = 0;

export function embeddingsHealthy(): "ok" | "down" | "unconfigured" {
  if (!endpoint().key()) return "unconfigured";
  if (getEmbeddingGuardError()) return "down";
  if (lastFailAt > lastOkAt && Date.now() - lastFailAt < 5 * 60_000) return "down";
  return "ok";
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function normalize(v: number[]): number[] {
  let n = 0;
  for (const x of v) n += x * x;
  n = Math.sqrt(n) || 1;
  return v.map((x) => x / n);
}

async function embedBatch(batch: string[], kind: "document" | "query"): Promise<number[][]> {
  let useInputType = true;
  let lastErr = "";
  for (let attempt = 1; attempt <= MAX_TRIES; attempt++) {
    const t0 = Date.now();
    let status = 0;
    try {
      const res = await fetch(endpoint().url, {
        method: "POST",
        headers: { Authorization: `Bearer ${endpoint().key()}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          model: config.embeddingModel,
          input: batch,
          dimensions: config.embeddingDimensions,
          ...(useInputType ? { input_type: kind === "query" ? "query" : "passage" } : {}),
        }),
        signal: AbortSignal.timeout(60_000),
      });
      status = res.status;
      if (res.ok) {
        const json = (await res.json()) as { data?: Array<{ index?: number; embedding: number[] }> };
        const data = json.data ?? [];
        if (data.length !== batch.length) throw new Error(`expected ${batch.length} embeddings, got ${data.length}`);
        const sorted = [...data].sort((a, b) => (a.index ?? 0) - (b.index ?? 0));
        const out = sorted.map((d) => d.embedding);
        if (out.some((v) => v.length !== config.embeddingDimensions)) throw new Error("unexpected embedding dimensions");
        recordUsage({ provider: config.embeddingProvider, model: config.embeddingModel, kind: "embed", ok: true, status, latencyMs: Date.now() - t0, count: batch.length });
        lastOkAt = Date.now();
        return out.map(normalize);
      }
      const body = (await res.text()).slice(0, 200);
      lastErr = `HTTP ${status}: ${body}`;
      recordUsage({ provider: config.embeddingProvider, model: config.embeddingModel, kind: "embed", ok: false, status, latencyMs: Date.now() - t0, count: batch.length });
      if (status === 400 && useInputType) {
        useInputType = false; // some models reject input_type
        attempt--;
        continue;
      }
      if (status !== 429 && status < 500) break; // not retryable
      const retryAfter = Number(res.headers.get("retry-after"));
      await sleep(Number.isFinite(retryAfter) && retryAfter > 0 ? Math.min(retryAfter, 30) * 1000 : Math.min(2 ** attempt * 1000, 20_000));
    } catch (e) {
      lastErr = (e as Error).message.slice(0, 200);
      if (!status) recordUsage({ provider: config.embeddingProvider, model: config.embeddingModel, kind: "embed", ok: false, latencyMs: Date.now() - t0, count: batch.length });
      if (attempt < MAX_TRIES) await sleep(Math.min(2 ** attempt * 1000, 20_000));
    }
  }
  lastFailAt = Date.now();
  log.warn("embedding request failed", { reason: lastErr });
  throw new AppError(503, "unavailable", `Embedding service failed: ${lastErr}`.slice(0, 200), true);
}

/** 1024-dim, L2-normalized embeddings. Batches inputs; retries 429/5xx with backoff. */
export async function embedTexts(texts: string[], kind: "document" | "query", opts: { reembed?: boolean } = {}): Promise<number[][]> {
  if (!endpoint().key()) throw new AppError(503, "unavailable", `Embeddings not configured (${config.embeddingProvider} key missing)`);
  const guard = getEmbeddingGuardError();
  if (guard && !opts.reembed) throw new AppError(503, "unavailable", guard);
  const out: number[][] = [];
  const size = Math.max(1, config.embeddingBatchSize);
  for (let i = 0; i < texts.length; i += size) {
    const batch = texts.slice(i, i + size).map((t) => (t.length > MAX_CHARS ? t.slice(0, MAX_CHARS) : t) || " ");
    out.push(...(await embedBatch(batch, kind)));
  }
  return out;
}
