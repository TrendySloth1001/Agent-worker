// Deterministic cost simulation for embeddings: counts upstream embedding requests for batching,
// the query cache and the debounced conversation-recall indexing. Assertions lock the budgets in.
import assert from "node:assert/strict";
import { test } from "node:test";
import { config } from "../src/config.js";
import { embedQueries, embedTexts, stubQueryEmbedder } from "../src/embeddings/index.js";
import { IDLE_MS, IndexScheduler, MAX_SAVES, MAX_WAIT_MS, USER_GAP_MS } from "../src/recall/index.js";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const dims = config.embeddingDimensions;

test("embedTexts: chunks go out as arrays, not one request per chunk", async () => {
  const cfg = config as unknown as { nvidiaApiKey?: string; openrouterApiKey?: string };
  const keys = { n: cfg.nvidiaApiKey, o: cfg.openrouterApiKey };
  cfg.nvidiaApiKey ||= "test-key";
  cfg.openrouterApiKey ||= "test-key";
  const real = globalThis.fetch;
  let requests = 0;
  globalThis.fetch = (async (_url: unknown, init: { body: string }) => {
    requests++;
    const input = JSON.parse(init.body).input as string[];
    return new Response(JSON.stringify({ data: input.map((_, index) => ({ index, embedding: Array.from({ length: dims }, (_v, k) => (k === index % dims ? 1 : 0)) })) }), { status: 200 });
  }) as typeof fetch;
  try {
    const vecs = await embedTexts(Array.from({ length: 12 }, (_, i) => `chunk ${i}`), "document");
    assert.equal(vecs.length, 12);
    assert.equal(requests, 1, "an indexing run's chunks are one request");
    requests = 0;
    await embedTexts(Array.from({ length: config.embeddingBatchSize * 2 }, (_, i) => `chunk ${i}`), "document");
    assert.equal(requests, 2, "a big ingest is one request per provider batch");
    console.log(`embed requests: 12 chunks -> 1, ${config.embeddingBatchSize * 2} chunks -> 2 (was 1 per 16 chunks, sequential)`);
  } finally {
    globalThis.fetch = real;
    cfg.nvidiaApiKey = keys.n;
    cfg.openrouterApiKey = keys.o;
  }
});

test("embedQueries: identical queries within a turn and across turns cost one request", async () => {
  let requests = 0;
  const restore = stubQueryEmbedder(async (texts) => {
    requests++;
    return texts.map(() => Array.from({ length: dims }, () => 0.1));
  });
  try {
    // KB retrieval, chat recall and memory ask for the same text in one turn; a repeated question asks again later.
    await Promise.all([embedQueries(["capital of france"]), embedQueries(["capital of france"]), embedQueries(["capital of france", "other query"])]);
    await embedQueries(["capital of france"]);
    await embedQueries(["capital of france", "other query"]);
    assert.equal(requests, 1);
  } finally {
    restore();
  }
});

/** Runs a chat session of [turns] saves, [gapMs] apart, and counts the indexing runs. */
async function session(turns: number, gapMs: number, o: ConstructorParameters<typeof IndexScheduler>[1], userId = "u1"): Promise<{ runs: number; atEnd: number }> {
  let runs = 0;
  const s = new IndexScheduler(async () => void runs++, o);
  for (let i = 0; i < turns; i++) {
    s.schedule("chat-1", userId);
    await sleep(gapMs);
  }
  const atEnd = runs;
  await sleep((o.idleMs ?? 0) + 60);
  return { runs, atEnd };
}

test("recall indexing: a 10-message session is one indexing run, not one per message", async () => {
  // Time scaled down 1000x: idle 60 ms stands for 1 minute, saves 20 ms apart for 20 seconds.
  const debounced = await session(10, 20, { idleMs: 60, maxWaitMs: 10_000, maxSaves: 50, userGapMs: 0, settleMs: 5 });
  const old = await session(10, 20, { idleMs: 8, maxWaitMs: 10_000, maxSaves: 50, userGapMs: 0, settleMs: 5 }); // "20 s" debounce vs saves 20 s apart
  console.log(`indexing runs for 10 turns: debounced ${debounced.runs}, per-message debounce ${old.runs}`);
  assert.equal(debounced.runs, 1);
  assert.ok(old.runs >= 8);
});

test("recall indexing: a burst of saves flushes after a short settle, and the max wait bounds staleness", async () => {
  const burst = await session(20, 2, { idleMs: 500, maxWaitMs: 10_000, maxSaves: MAX_SAVES, userGapMs: 0, settleMs: 15 });
  assert.equal(burst.runs, 1);
  let runs = 0;
  const s = new IndexScheduler(async () => void runs++, { idleMs: 80, maxWaitMs: 150, maxSaves: 1000, userGapMs: 0 });
  for (let i = 0; i < 12; i++) {
    s.schedule("long-chat", "u1");
    await sleep(25);
  }
  assert.ok(runs >= 1, "indexed within the max wait although the user never went idle");
  s.cancel("long-chat");
});

test("recall indexing: one user's chats are indexed at most once per gap", async () => {
  const at: number[] = [];
  const s = new IndexScheduler(async () => void at.push(Date.now()), { idleMs: 5, userGapMs: 120, settleMs: 10 });
  s.schedule("a", "u1");
  s.schedule("b", "u1");
  s.schedule("c", "u2");
  await sleep(400);
  assert.equal(at.length, 3);
  const sorted = [...at].sort((x, y) => x - y);
  assert.ok(sorted[2] - sorted[0] >= 100, "the second chat of u1 waited for the gap");
});

test("recall indexing defaults: minutes of idle, bounded wait", () => {
  assert.ok(IDLE_MS >= 2 * 60_000 && IDLE_MS <= 5 * 60_000);
  assert.ok(MAX_WAIT_MS >= IDLE_MS && MAX_WAIT_MS <= 15 * 60_000);
  assert.ok(USER_GAP_MS >= 30_000);
});
