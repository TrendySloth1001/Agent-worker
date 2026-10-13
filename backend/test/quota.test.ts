import { test, afterEach } from "node:test";
import assert from "node:assert/strict";
import {
  classifyError,
  clearQuota,
  formatUntil,
  isQuotaBlocked,
  markQuota,
  nextUtcDayStart,
  nextUtcMonthStart,
  quotaGuard,
  QuotaBlockedError,
  quotaSnapshot,
  resetQuota,
  retryHintMs,
  setQuotaClock,
  setQuotaProber,
} from "../src/llm/quota.js";
import { ALL_BUSY_MESSAGE, ALL_QUOTA_MESSAGE, applyCooldown, ChatFailure, healthyFirst, preferForPrompt, runChat, type RunHooks } from "../src/llm/router.js";
import { VISION_MODELS } from "../src/llm/vision.js";
import { fallbackModels } from "../src/llm/stream-openrouter.js";
import { ThinkFilter, stripThink } from "../src/llm/think.js";
import { MODELS, clearCooldown, cooldownUntil, setCooldown } from "../src/models.js";
import { keepLatestImage, UpstreamError, type StreamHandle, type StreamUsage } from "../src/providers.js";

// The exact upstream messages seen in production.
const OLLAMA_MONTHLY = "you (sparky-account) have reached your monthly usage limit, upgrade for higher limits: https://ollama.com/upgrade (ref: 7f1c2a9e-0b1d-4c55-9a51-2d0c1f5e8b3a)";
const OR_BUSY = "Provider returned error";
const OR_PER_DAY = "Rate limit exceeded: free-models-per-day. Add 10 credits to unlock 1000 free model requests per day";
const GROQ_TPM = "Rate limit reached for model `openai/gpt-oss-120b` in organization `org_x` service tier `on_demand` on tokens per minute (TPM): Limit 8000, Used 7900, Requested 900. Please try again in 6.75s.";
const GROQ_RPD = "Rate limit reached for model `qwen/qwen3.8-27b` in organization `org_x` service tier `on_demand` on requests per day (RPD): Limit 1000, Used 1000, Requested 1. Please try again in 1m26.4s.";
const NV_BUSY = "ResourceExhausted: Worker local total request limit reached (16/16)";

const NOW = Date.UTC(2026, 9, 13, 12, 0, 0); // 13 Oct 2026 12:00 UTC

const err = (status: number, message: string, retryAfterMs?: number) => new UpstreamError(status, message, retryAfterMs);

afterEach(() => {
  resetQuota();
  setQuotaClock(null);
});

test("classify: Ollama's monthly usage limit is an account-wide quota until the next UTC month", () => {
  const c = classifyError("ollama:gpt-oss:120b", err(429, OLLAMA_MONTHLY), NOW);
  assert.equal(c.kind, "quota_exhausted");
  assert.ok(c.kind === "quota_exhausted");
  assert.equal(c.window, "month");
  assert.equal(c.scope, "provider");
  assert.equal(new Date(c.untilMs).toISOString(), "2026-11-01T00:00:00.000Z");
});

test("classify: OpenRouter 'Provider returned error' is upstream-busy (next model now), not our quota", () => {
  const c = classifyError("openrouter:google/gemma-4-31b-it:free", err(429, OR_BUSY), NOW);
  assert.equal(c.kind, "upstream_busy");
  assert.ok(c.kind === "upstream_busy" && c.cooldownMs <= 60_000);
});

test("classify: OpenRouter free-models-per-day and 402 are provider quotas", () => {
  const day = classifyError("openrouter:google/gemma-4-31b-it:free", err(429, OR_PER_DAY), NOW);
  assert.ok(day.kind === "quota_exhausted");
  assert.equal(day.window, "day");
  assert.equal(day.scope, "provider");
  assert.equal(new Date(day.untilMs).toISOString(), "2026-10-14T00:00:00.000Z");
  const billing = classifyError("openrouter:x/y", err(402, "Insufficient credits. Add more using https://openrouter.ai/credits"), NOW);
  assert.ok(billing.kind === "quota_exhausted");
  assert.equal(billing.scope, "provider");
  assert.equal(billing.untilMs, NOW + 6 * 3_600_000);
});

test("classify: Groq per-minute windows are rate limits; a per-day window is a model quota with its own retry hint", () => {
  const tpm = classifyError("groq:openai/gpt-oss-120b", err(429, GROQ_TPM), NOW);
  assert.deepEqual(tpm, { kind: "rate_limited", cooldownMs: 6750 });
  const rpd = classifyError("groq:qwen/qwen3.8-27b", err(429, GROQ_RPD), NOW);
  assert.ok(rpd.kind === "quota_exhausted");
  assert.equal(rpd.window, "day");
  assert.equal(rpd.scope, "model");
  assert.equal(rpd.untilMs, NOW + 86_400);
  // Retry-After header wins over the default.
  assert.deepEqual(classifyError("nvidia:x/y", err(429, "Too Many Requests", 12_000), NOW), { kind: "rate_limited", cooldownMs: 12_000 });
});

test("classify: busy NVIDIA workers, timeouts and auth errors", () => {
  assert.equal(classifyError("nvidia:x/y", err(500, NV_BUSY), NOW).kind, "transient");
  assert.equal(classifyError("nvidia:x/y", err(0, "timeout waiting for response"), NOW).kind, "transient");
  assert.equal(classifyError("groq:x", err(401, "Invalid API Key"), NOW).kind, "auth");
  assert.equal(classifyError("groq:x", err(400, "bad request"), NOW).kind, "other");
  assert.equal(classifyError("ollama:x", new QuotaBlockedError({ scope: "ollama", provider: "ollama", until: NOW }), NOW).kind, "blocked");
});

test("cooldown windows: next UTC month (across the year end) and next UTC day", () => {
  assert.equal(new Date(nextUtcMonthStart(Date.UTC(2026, 11, 31, 23, 59))).toISOString(), "2027-01-01T00:00:00.000Z");
  assert.equal(new Date(nextUtcMonthStart(Date.UTC(2026, 9, 1, 0, 0))).toISOString(), "2026-11-01T00:00:00.000Z");
  assert.equal(new Date(nextUtcDayStart(Date.UTC(2026, 9, 31, 23, 0))).toISOString(), "2026-11-01T00:00:00.000Z");
  assert.equal(retryHintMs("Please try again in 1m26.4s."), 86_400);
  assert.equal(retryHintMs("retry after 30 seconds"), 30_000);
  assert.equal(retryHintMs("nothing here"), undefined);
  assert.equal(formatUntil(Date.UTC(2026, 10, 1)), "1 Nov");
  assert.equal(formatUntil(Date.UTC(2026, 9, 14, 13, 5)), "14 Oct 13:05 UTC");
});

test("an exhausted Ollama quota blocks every Ollama model and web search, logs once, and shows in telemetry", () => {
  const warn = console.warn;
  const lines: string[] = [];
  console.warn = (...a: unknown[]) => void lines.push(a.join(" "));
  try {
    for (const id of ["ollama:gpt-oss:120b", "ollama:gemma4:31b", "ollama:gpt-oss:120b"]) applyCooldown(id, err(429, OLLAMA_MONTHLY));
  } finally {
    console.warn = warn;
  }
  assert.equal(lines.filter((l) => l.includes("provider quota exhausted")).length, 1);
  for (const m of MODELS.filter((m) => m.provider === "ollama")) {
    assert.equal(isQuotaBlocked(m.id), true, m.id);
    assert.notEqual(cooldownUntil(m.id), null, m.id);
  }
  assert.equal(isQuotaBlocked("ollama:web_search"), true);
  assert.equal(isQuotaBlocked("groq:openai/gpt-oss-120b"), false);
  assert.throws(() => quotaGuard("ollama:nemotron-3-super"), QuotaBlockedError);
  const snap = quotaSnapshot();
  assert.equal(snap.length, 1);
  assert.match(snap[0].label, /^Ollama: quota exhausted until 1 (Nov|Dec|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct)$/);

  // A successful call (or probe) lifts the block for the whole provider.
  clearQuota("ollama:gpt-oss:20b");
  assert.equal(isQuotaBlocked("ollama:gemma4:31b"), false);
  assert.equal(cooldownUntil("ollama:gemma4:31b"), null);
});

test("a blocked scope is re-probed at most once per probe window; a successful probe restores it", async () => {
  let now = NOW;
  setQuotaClock(() => now);
  const probes: string[] = [];
  let probeOk = false;
  setQuotaProber(async (id) => {
    probes.push(id);
    if (!probeOk) throw err(429, OLLAMA_MONTHLY);
  });
  markQuota("ollama:gemma4:31b", { kind: "quota_exhausted", window: "month", scope: "provider", untilMs: nextUtcMonthStart(now) });
  assert.equal(isQuotaBlocked("ollama:gpt-oss:120b"), true);
  assert.equal(probes.length, 0, "no probe right away");
  now += 6 * 3_600_000 + 1;
  isQuotaBlocked("ollama:gpt-oss:120b");
  isQuotaBlocked("ollama:gpt-oss:120b");
  await new Promise((r) => setImmediate(r));
  assert.deepEqual(probes, ["ollama:gpt-oss:20b"], "one cheap probe per window");
  assert.equal(isQuotaBlocked("ollama:gpt-oss:120b"), true, "failed probe keeps the block");
  now += 6 * 3_600_000 + 1;
  probeOk = true;
  isQuotaBlocked("ollama:gpt-oss:120b");
  await new Promise((r) => setImmediate(r));
  assert.equal(probes.length, 2);
  assert.equal(isQuotaBlocked("ollama:gpt-oss:120b"), false);
  setQuotaProber(null);
});

test("the block ends by itself when the window is over", () => {
  let now = NOW;
  setQuotaClock(() => now);
  markQuota("groq:qwen/qwen3.8-27b", { kind: "quota_exhausted", window: "day", scope: "model", untilMs: now + 60_000 });
  assert.equal(isQuotaBlocked("groq:qwen/qwen3.8-27b"), true);
  assert.equal(isQuotaBlocked("groq:openai/gpt-oss-20b"), false, "model scope only");
  now += 60_001;
  assert.equal(isQuotaBlocked("groq:qwen/qwen3.8-27b"), false);
});

// ---- router -------------------------------------------------------------------------

type Script = (usage: StreamUsage) => AsyncGenerator<string>;
function stubStream(scripts: Record<string, Script>, calls: string[]) {
  return async (id: string): Promise<StreamHandle> => {
    calls.push(id);
    const usage: StreamUsage = { promptTokens: 10, completionTokens: 5, finishReason: null, completed: false };
    const script = scripts[id] ?? (async function* () {
      throw err(500, "no script");
    });
    return { tokens: script(usage), usage };
  };
}
const ok = (text: string): Script =>
  async function* (usage) {
    yield text;
    usage.completed = true;
    usage.finishReason = "stop";
  };
const fail = (status: number, message: string): Script =>
  async function* () {
    throw err(status, message);
  };

function hooks() {
  const out = { deltas: [] as string[], models: [] as string[], resets: 0, fallbacks: [] as string[] };
  const h: RunHooks = {
    onQueued() {},
    onModel: (m) => void out.models.push(m),
    onDelta: (t) => void out.deltas.push(t),
    onReset: () => void out.resets++,
    onFallback: (from, to) => void out.fallbacks.push(`${from}->${to}`),
  };
  return { h, out };
}

const cleanup = (ids: string[]) => ids.forEach((id) => clearCooldown(id));

test("router: Auto skips a provider whose quota is exhausted without calling it", async () => {
  markQuota("ollama:gpt-oss:120b", { kind: "quota_exhausted", window: "month", scope: "provider", untilMs: Date.now() + 3_600_000 });
  const calls: string[] = [];
  const { h, out } = hooks();
  const r = await runChat(["ollama:gpt-oss:120b", "ollama:gemma4:31b", "groq:openai/gpt-oss-120b"], [{ role: "user", content: "hi" }], new AbortController().signal, h, true, {
    stream: stubStream({ "groq:openai/gpt-oss-120b": ok("Hello") }, calls),
  });
  assert.equal(r.model, "groq:openai/gpt-oss-120b");
  assert.deepEqual(calls, ["groq:openai/gpt-oss-120b"]);
  assert.deepEqual(out.deltas, ["Hello"]);
  cleanup(["groq:openai/gpt-oss-120b"]);
});

test("router: an explicitly chosen model with an exhausted quota fails with a human message", async () => {
  markQuota("ollama:gpt-oss:120b", { kind: "quota_exhausted", window: "month", scope: "provider", untilMs: Date.UTC(2026, 10, 1) + 365 * 86_400_000 });
  const { h } = hooks();
  await assert.rejects(
    runChat(["ollama:gpt-oss:120b"], [{ role: "user", content: "hi" }], new AbortController().signal, h, false, { stream: stubStream({}, []) }),
    (e: unknown) => e instanceof ChatFailure && e.code === "model_busy" && /^Ollama has used up its quota until 1 Nov/.test(e.message),
  );
});

test("router: a quota error met mid-turn blocks the provider and Auto moves on", async () => {
  const calls: string[] = [];
  const { h } = hooks();
  const ids = ["ollama:gpt-oss:120b", "ollama:gemma4:31b", "nvidia:z-ai/glm-5.3-flash"];
  const r = await runChat(ids, [{ role: "user", content: "hi" }], new AbortController().signal, h, true, {
    stream: stubStream({ "ollama:gpt-oss:120b": fail(429, OLLAMA_MONTHLY), "nvidia:z-ai/glm-5.3-flash": ok("Hi!") }, calls),
  });
  assert.equal(r.model, "nvidia:z-ai/glm-5.3-flash");
  assert.deepEqual(calls, ["ollama:gpt-oss:120b", "nvidia:z-ai/glm-5.3-flash"], "the second Ollama model is never called");
  cleanup(ids);
});

test("router: a reply that is only <think> (no visible text) falls back to the next model", async () => {
  const calls: string[] = [];
  const { h, out } = hooks();
  const ids = ["groq:openai/gpt-oss-20b", "nvidia:nvidia/nemotron-3.5-lightning-30b-a3b"];
  const r = await runChat(ids, [{ role: "user", content: "hey" }], new AbortController().signal, h, true, {
    stream: stubStream(
      {
        "groq:openai/gpt-oss-20b": async function* (usage) {
          yield "<thi";
          yield "nk>the user says hey, ";
          yield "so greet</think>\n  ";
          usage.completed = true;
        },
        "nvidia:nvidia/nemotron-3.5-lightning-30b-a3b": ok("Hey there!"),
      },
      calls,
    ),
  });
  assert.equal(r.model, "nvidia:nvidia/nemotron-3.5-lightning-30b-a3b");
  assert.deepEqual(calls, ids);
  assert.deepEqual(out.models, ["nvidia:nvidia/nemotron-3.5-lightning-30b-a3b"], "the empty model never became the visible one");
  assert.equal(out.deltas.join(""), "Hey there!");
  cleanup(ids);
});

test("router: visible text after a think block is streamed without the reasoning", async () => {
  const { h, out } = hooks();
  await runChat(["groq:qwen/qwen3.8-27b"], [{ role: "user", content: "q" }], new AbortController().signal, h, true, {
    stream: stubStream(
      {
        "groq:qwen/qwen3.8-27b": async function* (usage) {
          yield "<think>plan</th";
          yield "ink>Answer ";
          yield "here.";
          usage.completed = true;
        },
      },
      [],
    ),
  });
  assert.equal(out.deltas.join(""), "Answer here.");
  cleanup(["groq:qwen/qwen3.8-27b"]);
});

test("zero-candidate guard: when every usable model is cooling down, Auto still tries them, soonest first", async () => {
  const ids = ["groq:openai/gpt-oss-120b", "nvidia:nvidia/nemotron-3-super-120b-a12b", "groq:openai/gpt-oss-20b"];
  setCooldown(ids[0], 120_000);
  setCooldown(ids[1], 30_000);
  setCooldown(ids[2], 60_000);
  const ordered = healthyFirst(ids);
  assert.deepEqual(ordered, [ids[1], ids[2], ids[0]]);
  // With one healthy model, only the healthy ones are offered.
  clearCooldown(ids[2]);
  assert.deepEqual(healthyFirst(ids), [ids[2]]);
  setCooldown(ids[2], 60_000);

  // runChat no longer skips cooled models down to the last one: it tries them in order.
  const calls: string[] = [];
  const { h } = hooks();
  const r = await runChat(ordered, [{ role: "user", content: "hi" }], new AbortController().signal, h, true, {
    stream: stubStream({ [ids[1]]: fail(429, "Too Many Requests"), [ids[2]]: ok("ok") }, calls),
  });
  assert.equal(r.model, ids[2]);
  assert.deepEqual(calls, [ids[1], ids[2]]);
  cleanup(ids);
});

test("zero-candidate guard: soft prompt-size preferences never empty the list", () => {
  assert.deepEqual(preferForPrompt(["groq:openai/gpt-oss-120b"], 30_000), ["groq:openai/gpt-oss-120b"]);
  assert.deepEqual(preferForPrompt(["groq:openai/gpt-oss-120b", "nvidia:z-ai/glm-5.3-flash"], 30_000), ["nvidia:z-ai/glm-5.3-flash"]);
});

test("router: when every model fails the user gets a human message, code all_models_failed", async () => {
  const ids = ["groq:openai/gpt-oss-120b", "nvidia:z-ai/glm-5.3-flash"];
  const { h } = hooks();
  await assert.rejects(
    runChat(ids, [{ role: "user", content: "hi" }], new AbortController().signal, h, true, { stream: stubStream({}, []) }),
    (e: unknown) => e instanceof ChatFailure && e.code === "all_models_failed" && e.message === ALL_BUSY_MESSAGE,
  );
  cleanup(ids);
  markQuota("ollama:gpt-oss:120b", { kind: "quota_exhausted", window: "month", scope: "provider", untilMs: Date.now() + 3_600_000 });
  await assert.rejects(
    runChat(["ollama:gpt-oss:120b", "ollama:gemma4:31b"], [{ role: "user", content: "hi" }], new AbortController().signal, h, true, { stream: stubStream({}, []) }),
    (e: unknown) => e instanceof ChatFailure && e.code === "all_models_failed" && e.message === ALL_QUOTA_MESSAGE,
  );
});

// ---- vision -----------------------------------------------------------------------

test("vision chain: every provider contributes, most reliable first", () => {
  assert.deepEqual(VISION_MODELS, [
    "groq:qwen/qwen3.8-27b",
    "nvidia:nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
    "nvidia:meta/llama-3.2-11b-vision-instruct",
    "ollama:gemma4:31b",
    "openrouter:nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free",
    "openrouter:google/gemma-4-31b-it:free",
    "openrouter:google/gemma-4-26b-a4b-it:free",
  ]);
  // OpenRouter's server-side fallbacks for an image request are vision models only.
  const alts = fallbackModels("google/gemma-4-31b-it:free", true);
  assert.ok(alts.length >= 1);
  assert.ok(alts.every((m) => VISION_MODELS.includes(`openrouter:${m}`) && m !== "google/gemma-4-31b-it:free"));
});

test("vision chain: quota-exhausted Ollama, cooling Groq and busy NVIDIA fall through to the next vision model", async () => {
  markQuota("ollama:gemma4:31b", { kind: "quota_exhausted", window: "month", scope: "provider", untilMs: Date.now() + 3_600_000 });
  const calls: string[] = [];
  const { h } = hooks();
  // Production shape: Groq's vision model cooling down, Ollama out of quota; NVIDIA's workers busy.
  setCooldown("groq:qwen/qwen3.8-27b", 60_000);
  const chain = healthyFirst(VISION_MODELS.filter((id) => !isQuotaBlocked(id)));
  assert.ok(!chain.includes("ollama:gemma4:31b"));
  const r = await runChat(chain, [{ role: "user", content: "what is this?", images: ["AAAA"] }], new AbortController().signal, h, true, {
    stream: stubStream(
      {
        "nvidia:nvidia/nemotron-3-nano-omni-30b-a3b-reasoning": fail(500, NV_BUSY),
        "nvidia:meta/llama-3.2-11b-vision-instruct": fail(0, "timeout waiting for response"),
        "openrouter:nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free": ok("A red square."),
      },
      calls,
    ),
  });
  assert.equal(r.model, "openrouter:nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free");
  assert.deepEqual(calls, ["nvidia:nvidia/nemotron-3-nano-omni-30b-a3b-reasoning", "nvidia:meta/llama-3.2-11b-vision-instruct", "openrouter:nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"]);
  cleanup(VISION_MODELS);
});

test("Llama 3.2 Vision gets only the newest image", () => {
  const out = keepLatestImage([
    { role: "user", content: "a", images: ["1", "2"] },
    { role: "assistant", content: "b" },
    { role: "user", content: "c", images: ["3", "4"] },
  ]);
  assert.equal(out[0].images, undefined);
  assert.deepEqual(out[2].images, ["4"]);
});

test("ThinkFilter handles tags split across chunks and unclosed blocks", () => {
  const f = new ThinkFilter();
  assert.equal(f.push("Hi <"), "Hi ");
  assert.equal(f.push("think>x</thi"), "");
  assert.equal(f.push("nk> there"), " there");
  assert.equal(f.push(" <3"), " <3");
  assert.equal(f.push(" <th"), " ");
  assert.equal(f.flush(), "<th");
  const g = new ThinkFilter();
  assert.equal(g.push("<think>never closed"), "");
  assert.equal(g.flush(), "");
  assert.equal(stripThink("<think>a</think>b<think>c"), "b");
});
