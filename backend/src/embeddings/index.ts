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
      recordUsage({ provider: config.embeddingProvider, model: config.embeddingModel, kind: "embed", ok: false, status, latencyMs: Date.now() - t0, count: batch.length, errorMessage: lastErr });
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
      recordUsage({ provider: config.embeddingProvider, model: config.embeddingModel, kind: "embed", ok: false, status: status || undefined, latencyMs: Date.now() - t0, count: batch.length, errorMessage: lastErr });
      if (attempt < MAX_TRIES) await sleep(Math.min(2 ** attempt * 1000, 20_000));
    }
  }
  lastFailAt = Date.now();
  log.warn("embedding request failed", { reason: lastErr });
  throw new AppError(503, "unavailable", `Embedding service failed: ${lastErr}`.slice(0, 200), true);
}

const BATCH_CONCURRENCY = 2;

/** 1024-dim, L2-normalized embeddings. Batches inputs (two requests in flight); retries 429/5xx with backoff. */
export async function embedTexts(texts: string[], kind: "document" | "query", opts: { reembed?: boolean } = {}): Promise<number[][]> {
  if (!endpoint().key()) throw new AppError(503, "unavailable", `Embeddings not configured (${config.embeddingProvider} key missing)`);
  const guard = getEmbeddingGuardError();
  if (guard && !opts.reembed) throw new AppError(503, "unavailable", guard);
  const size = Math.max(1, config.embeddingBatchSize);
  const batches: string[][] = [];
  for (let i = 0; i < texts.length; i += size) {
    batches.push(texts.slice(i, i + size).map((t) => (t.length > MAX_CHARS ? t.slice(0, MAX_CHARS) : t) || " "));
  }
  const results: number[][][] = new Array(batches.length);
  let next = 0;
  const worker = async () => {
    for (let i = next++; i < batches.length; i = next++) results[i] = await embedBatch(batches[i], kind);
  };
  await Promise.all(Array.from({ length: Math.min(BATCH_CONCURRENCY, batches.length) }, worker));
  return results.flat();
}

// ---- query embedding cache ---------------------------------------------------
// Follow-up turns, rewrites and repeated searches embed the same text again:
// a small LRU keeps those off the (rate-limited, ~200-600 ms) network path.

const QUERY_CACHE_MAX = 256;
const QUERY_CACHE_TTL_MS = 30 * 60_000;
const queryCache = new Map<string, { v: number[]; at: number }>();
const cacheKey = (t: string) => `${config.embeddingModel}|${config.embeddingDimensions}|${t}`;

/** Query embeddings with an LRU cache; only the misses hit the network (in one batch). */
export async function embedQueries(texts: string[]): Promise<number[][]> {
  const now = Date.now();
  const out: Array<number[] | undefined> = texts.map((t) => {
    const k = cacheKey(t);
    const hit = queryCache.get(k);
    if (!hit || now - hit.at > QUERY_CACHE_TTL_MS) return undefined;
    queryCache.delete(k); // refresh recency
    queryCache.set(k, hit);
    return hit.v;
  });
  const missIdx = out.flatMap((v, i) => (v ? [] : [i]));
  if (missIdx.length) {
    const unique = [...new Set(missIdx.map((i) => texts[i]))];
    const vecs = await embedTexts(unique, "query");
    const byText = new Map(unique.map((t, i) => [t, vecs[i]]));
    for (const [t, v] of byText) {
      queryCache.set(cacheKey(t), { v, at: now });
      if (queryCache.size > QUERY_CACHE_MAX) queryCache.delete(queryCache.keys().next().value as string);
    }
    for (const i of missIdx) out[i] = byText.get(texts[i]);
  }
  return out as number[][];
}
