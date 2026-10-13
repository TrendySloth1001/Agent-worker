import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import type { Request, Response } from "express";
import {
  BudgetBlockedError,
  budgetSnapshot,
  check,
  estimateRequestTokens,
  guard,
  IMAGE_TOKENS,
  reserve,
  resetBudget,
  setBudgetClock,
} from "../src/llm/budget.js";
import { QuotaBlockedError, resetQuota } from "../src/llm/quota.js";
import { clearRateSnapshots, setSnapshot } from "../src/usage/rateLimits.js";
import { Slots } from "../src/llm/slots.js";
import { auxGate, auxOnce, resetAux } from "../src/llm/aux.js";
import { runChat, withSlot, type RunHooks } from "../src/llm/router.js";
import { inFlightLimit, rateLimit } from "../src/util/rateLimit.js";
import { AppError } from "../src/util/errors.js";
import { USER_MSG } from "../src/util/userMessages.js";
import type { StreamHandle, StreamUsage } from "../src/providers.js";

const GROQ = "groq:openai/gpt-oss-120b";
const NVIDIA = "nvidia:nvidia/nemotron-3-super-120b-a12b";
const T0 = Date.UTC(2026, 9, 13, 12, 0, 0);
let now = T0;

beforeEach(() => {
  now = T0;
  setBudgetClock(() => now);
  resetBudget();
  resetAux();
  resetQuota();
  clearRateSnapshots();
});

// ---- budget pre-checks -------------------------------------------------------------

test("budget: estimates count text, images and a capped reply reserve", () => {
  const t = estimateRequestTokens([{ role: "user", content: "x".repeat(350), images: ["a", "b"] }], 8192);
  assert.equal(t, 100 + 2 * IMAGE_TOKENS + 1_500);
  assert.equal(estimateRequestTokens([{ role: "user", content: "x".repeat(35) }], 200), 10 + 200);
});

test("budget: a Groq model is skipped once its minute token window would overflow, and recovers", () => {
  // 8k TPM with 10% headroom: 7,200 usable.
  reserve(GROQ, 4_000);
  now += 10_000;
  reserve(GROQ, 3_000);
  const v = check(GROQ, 1_000);
  assert.equal(v.ok, false);
  assert.equal(!v.ok && v.reason, "tpm");
  // The first 4k roll off 60 s after they were spent.
  assert.equal(!v.ok && v.waitMs, 50_000);
  // Other models (and providers) are unaffected.
  assert.equal(check("groq:qwen/qwen3.8-27b", 1_000).ok, true);
  assert.equal(check(NVIDIA, 1_000).ok, true);
  now += 50_000;
  assert.equal(check(GROQ, 1_000).ok, true);
});

test("budget: settle replaces the estimate with the real token count", () => {
  const r = reserve(GROQ, 7_000);
  assert.equal(check(GROQ, 1_000).ok, false);
  r.settle(500);
  assert.equal(check(GROQ, 1_000).ok, true);
});

test("budget: requests per minute count across a provider account (NVIDIA)", () => {
  for (let i = 0; i < 36; i++) reserve(i % 2 ? NVIDIA : "nvidia:openai/gpt-oss-20b", 10);
  const v = check("nvidia:z-ai/glm-5.3-flash", 10);
  assert.equal(!v.ok && v.reason, "rpm");
});

test("budget: a request larger than the whole minute window never fits", () => {
  const v = check(GROQ, 9_000);
  assert.equal(!v.ok && v.reason, "too_large");
});

test("budget: the daily request window resets at UTC midnight", () => {
  for (let i = 0; i < 900; i++) reserve(GROQ, 0);
  now += 61_000; // minute window clear, day window full
  const v = check(GROQ, 10);
  assert.equal(!v.ok && v.reason, "rpd");
  now = Date.UTC(2026, 9, 14, 0, 0, 1);
  assert.equal(check(GROQ, 10).ok, true);
});

test("budget: response headers are trusted, minus what was spent since they arrived", () => {
  setSnapshot(GROQ, {
    limitRequests: 1000,
    remainingRequests: 500,
    resetsAt: new Date(now + 3_600_000).toISOString(),
    limitTokens: 6_000,
    remainingTokens: 2_000,
    tokensResetAt: new Date(now + 20_000).toISOString(),
    at: new Date(now - 1_000).toISOString(),
  });
  assert.equal(check(GROQ, 1_500).ok, true);
  reserve(GROQ, 1_000);
  const v = check(GROQ, 1_500);
  assert.equal(!v.ok && v.reason, "header_tokens");
  assert.equal(!v.ok && v.waitMs, 20_000);
  // The header's own limit (6k for this model) replaces the default 8k.
  assert.equal(!check(GROQ, 6_500).ok, true);
});

test("budget: guard throws a cheap skip that the router treats like a quota block", () => {
  reserve(GROQ, 7_000);
  assert.throws(
    () => guard(GROQ, 1_000),
    (e: unknown) => e instanceof BudgetBlockedError && e instanceof QuotaBlockedError && e.reason === "tpm",
  );
  assert.ok(budgetSnapshot().skips.some((s) => s.model === GROQ && s.reason === "tpm"));
});

// ---- router -------------------------------------------------------------------------

function stub(calls: string[]) {
  return async (id: string): Promise<StreamHandle> => {
    calls.push(id);
    const usage: StreamUsage = { promptTokens: 10, completionTokens: 5, finishReason: "stop", completed: false };
    return {
      usage,
      tokens: (async function* () {
        yield "hi";
        usage.completed = true;
      })(),
    };
  };
}
const quietHooks = (onQueued = () => {}): RunHooks => ({ onQueued, onModel() {}, onDelta() {}, onReset() {}, onFallback() {} });

test("router: Auto tries a model that fits its budget before one that doesn't", async () => {
  reserve(GROQ, 7_000);
  const calls: string[] = [];
  const r = await runChat([GROQ, NVIDIA], [{ role: "user", content: "hello" }], new AbortController().signal, quietHooks(), true, { stream: stub(calls) });
  assert.equal(r.model, NVIDIA);
  assert.deepEqual(calls, [NVIDIA]);
});

test("router: when nothing fits but a window frees within seconds, the turn waits instead of failing", async () => {
  setBudgetClock(null);
  resetBudget();
  // 36 requests this minute on Groq's per-model rpm (30 * 0.9 = 27): fill it with entries that expire in ~1 s.
  const real = Date.now();
  setBudgetClock(() => real - 59_000);
  for (let i = 0; i < 27; i++) reserve(GROQ, 1);
  setBudgetClock(null);
  assert.equal(check(GROQ, 10).ok, false);
  let queued = 0;
  const calls: string[] = [];
  const started = Date.now();
  const r = await runChat([GROQ], [{ role: "user", content: "hi" }], new AbortController().signal, quietHooks(() => queued++), false, { stream: stub(calls) });
  assert.equal(r.model, GROQ);
  assert.equal(queued, 1);
  assert.ok(Date.now() - started >= 900);
  assert.ok(budgetSnapshot().waits.count >= 1);
});

// ---- concurrency -------------------------------------------------------------------------

test("slots: main work is served before queued aux work, and aux never takes the last slot", async () => {
  const s = new Slots(2);
  const sig = new AbortController().signal;
  const a = await s.acquire(sig);
  assert.equal(s.auxSpare, 0, "the last free slot is kept for main work");
  await assert.rejects(s.acquire(sig, { priority: "aux", maxWaitMs: 30 }), /slot_busy/);
  const b = await s.acquire(sig);
  const order: string[] = [];
  const aux = s.acquire(sig, { priority: "aux", maxWaitMs: 1_000 }).then((r) => (order.push("aux"), r));
  const main = s.acquire(sig).then((r) => (order.push("main"), r));
  a();
  (await main)();
  b();
  (await aux)();
  assert.deepEqual(order, ["main", "aux"]);
});

test("slots: a single-slot provider queues main requests in order", async () => {
  const s = new Slots(1);
  const sig = new AbortController().signal;
  const first = await s.acquire(sig);
  let waited = 0;
  const second = s.acquire(sig, { onWait: () => waited++ });
  assert.equal(s.queued, 1);
  first();
  (await second)();
  assert.equal(waited, 1);
  assert.equal(s.inUse, 0);
});

test("withSlot: aux work gives up quickly when the provider has no spare slot", async () => {
  const sig = new AbortController().signal;
  // Ollama has one slot: hold it with main work.
  let release!: () => void;
  const held = withSlot("ollama:gpt-oss:20b", sig, () => new Promise<void>((r) => (release = r)));
  await new Promise((r) => setTimeout(r, 5));
  await assert.rejects(
    withSlot("ollama:gpt-oss:20b", sig, async () => "x", { priority: "aux", purpose: "title" }),
    (e: unknown) => e instanceof BudgetBlockedError && e.reason === "aux_deferred",
  );
  release();
  await held;
  assert.equal(budgetSnapshot().auxDeferred.title, 1);
});

// ---- aux deferral + dedupe ----------------------------------------------------------------

test("aux: deferred while the budget is tight, so the answer keeps its headroom", () => {
  // 5k of 7.2k used: a main call of 1k still fits, an aux call (needs 2k headroom on top) does not.
  reserve(GROQ, 5_000);
  assert.equal(check(GROQ, 1_000).ok, true);
  assert.throws(() => auxGate(GROQ, 1_000, "suggestions"), (e: unknown) => e instanceof BudgetBlockedError && e.reason === "aux_deferred");
  assert.equal(budgetSnapshot().auxDeferred.suggestions, 1);
  assert.doesNotThrow(() => auxGate(NVIDIA, 1_000, "suggestions"));
});

test("aux: identical requests share one call (in flight and cached)", async () => {
  let calls = 0;
  const msgs = [{ role: "user" as const, content: "title this" }];
  const fn = async () => {
    calls++;
    await new Promise((r) => setTimeout(r, 10));
    return "A title";
  };
  const [a, b] = await Promise.all([auxOnce("title", msgs, fn), auxOnce("title", msgs, fn)]);
  assert.equal(a, "A title");
  assert.equal(b, "A title");
  assert.equal(await auxOnce("title", msgs, fn), "A title");
  assert.equal(calls, 1);
  // A different purpose or text is a different request; failures are not cached.
  await auxOnce("memory", msgs, fn);
  assert.equal(calls, 2);
  await assert.rejects(auxOnce("title", [{ role: "user", content: "x" }], async () => Promise.reject(new Error("boom"))));
  assert.equal(await auxOnce("title", [{ role: "user", content: "x" }], async () => "ok"), "ok");
});

// ---- per-user caps ---------------------------------------------------------------------------

const req = (userId: string, body: unknown = {}) => ({ ip: "1.1.1.1", path: "/chat", body, user: { id: userId } }) as unknown as Request;
const res = () => Object.assign(new EventEmitter(), { setHeader() {} }) as unknown as Response & EventEmitter;
const call = (mw: (q: Request, r: Response, n: (e?: unknown) => void) => unknown, q: Request, r: Response) =>
  new Promise<unknown>((resolve) => void mw(q, r, (e) => resolve(e ?? null)));

test("per-user in-flight cap: a burst waits for the user's own earlier request, then proceeds", async () => {
  const mw = inFlightLimit(2, 500, "chat");
  const r1 = res();
  const r2 = res();
  assert.equal(await call(mw, req("u1"), r1), null);
  assert.equal(await call(mw, req("u1"), r2), null);
  // Another user is not affected.
  assert.equal(await call(mw, req("u2"), res()), null);
  const third = call(mw, req("u1"), res());
  setTimeout(() => r1.emit("close"), 50);
  assert.equal(await third, null);
  assert.equal(mw.inFlight("u:u1"), 2);
});

test("per-user in-flight cap: past the short queue the user gets the friendly slow-down", async () => {
  const mw = inFlightLimit(1, 30, "chat");
  assert.equal(await call(mw, req("u3"), res()), null);
  const err = await call(mw, req("u3"), res());
  assert.ok(err instanceof AppError);
  assert.equal((err as AppError).code, "rate_limited");
  assert.equal((err as AppError).message, USER_MSG.slowDown);
  assert.ok((budgetSnapshot().userCaps.chat ?? 0) >= 1);
});

test("per-user caps: the Round Table limit counts only Round Table runs", () => {
  const mw = rateLimit(1, 60_000, "auto", { name: "round-table", when: (q) => q.body?.roundTable === true });
  const run = (q: Request) => {
    let e: unknown = null;
    mw(q, res(), (x) => (e = x ?? null));
    return e;
  };
  assert.equal(run(req("u4", { roundTable: true })), null);
  assert.equal(run(req("u4", {})), null);
  const e = run(req("u4", { roundTable: true }));
  assert.ok(e instanceof AppError && e.message === USER_MSG.slowDown);
});
