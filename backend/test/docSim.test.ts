// Deterministic simulation: an 8-section document written the OLD way (every
// section sees the whole outline, every running summary and ~6 full sources,
// all sent to the same top models) versus the NEW planner -> writers -> editor
// flow, against mocked providers with per-minute limits and a virtual clock.
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { runPipeline, DEFAULT_LIMITS, type DocDeps } from "../src/docs/pipeline.js";
import { finishJob, registerJob, Semaphore } from "../src/docs/registry.js";
import { memoryStore } from "../src/docs/store.js";
import { sectionMessages } from "../src/prompts/doc.js";
import { ChatFailure } from "../src/llm/router.js";
import { UpstreamError, type Message } from "../src/providers.js";
import type { Outline, OutlineSection } from "../src/docs/types.js";

// ---- virtual clock -----------------------------------------------------------------

class VClock {
  t = 1_000_000;
  private timers: Array<{ at: number; seq: number; resolve: () => void }> = [];
  private seq = 0;
  now = () => this.t;
  sleep = (ms: number) => new Promise<void>((resolve) => this.timers.push({ at: this.t + Math.max(0, ms), seq: this.seq++, resolve }));
  async drive(work: Promise<unknown>): Promise<void> {
    let done = false;
    let failure: unknown;
    work.then(() => (done = true), (e) => ((failure = e), (done = true)));
    let idle = 0;
    while (!done) {
      for (let i = 0; i < 25 && !done; i++) await new Promise((r) => setImmediate(r));
      if (done) break;
      if (!this.timers.length) {
        if (++idle > 400) throw new Error("simulation stalled");
        continue;
      }
      idle = 0;
      this.timers.sort((a, b) => a.at - b.at || a.seq - b.seq);
      const next = this.timers.shift()!;
      this.t = Math.max(this.t, next.at);
      next.resolve();
    }
    if (failure) throw failure;
  }
}

// ---- mocked providers (free-plan style limits) ----------------------------------------

type Cfg = { scope: "model" | "provider"; rpm?: number; tpm?: number; concurrency?: number; msPerToken: number };
const PROVIDERS: Record<string, Cfg> = {
  groq: { scope: "model", rpm: 30, tpm: 8_000, msPerToken: 12 },
  nvidia: { scope: "provider", rpm: 40, msPerToken: 25 },
  openrouter: { scope: "provider", rpm: 20, msPerToken: 30 },
  ollama: { scope: "provider", concurrency: 1, msPerToken: 25 },
};
const providerOf = (id: string) => id.slice(0, id.indexOf(":"));

class Sim {
  calls = 0;
  rateLimited = 0;
  tokens = 0;
  private windows = new Map<string, Array<{ at: number; tokens: number }>>();
  private busy = new Map<string, Promise<void>>();
  constructor(private clock: VClock) {}

  private win(id: string) {
    const cfg = PROVIDERS[providerOf(id)];
    const key = cfg.scope === "model" ? id : providerOf(id);
    const w = (this.windows.get(key) ?? []).filter((e) => e.at > this.clock.now() - 60_000);
    this.windows.set(key, w);
    return w;
  }
  /** What a budget check would say (the router's own accounting keeps 10% back). */
  headroom(id: string, tokens: number): boolean {
    const cfg = PROVIDERS[providerOf(id)];
    const w = this.win(id);
    if (cfg.rpm && w.length + 1 > Math.floor(cfg.rpm * 0.9)) return false;
    if (cfg.tpm && w.reduce((n, e) => n + e.tokens, 0) + tokens > Math.floor(cfg.tpm * 0.9)) return false;
    return true;
  }
  async call(id: string, promptTokens: number, completionTokens: number): Promise<void> {
    const cfg = PROVIDERS[providerOf(id)];
    this.calls++;
    this.tokens += promptTokens; // the request was sent either way
    const w = this.win(id);
    if ((cfg.rpm && w.length >= cfg.rpm) || (cfg.tpm && w.reduce((n, e) => n + e.tokens, 0) + promptTokens + completionTokens > cfg.tpm)) {
      this.rateLimited++;
      await this.clock.sleep(300);
      throw new UpstreamError(429, "rate limited");
    }
    w.push({ at: this.clock.now(), tokens: promptTokens + completionTokens });
    const run = async () => {
      this.tokens += completionTokens;
      await this.clock.sleep(1_200 + completionTokens * cfg.msPerToken);
    };
    if (cfg.concurrency) {
      const prev = this.busy.get(providerOf(id)) ?? Promise.resolve();
      const mine = prev.then(run);
      this.busy.set(providerOf(id), mine.catch(() => {}));
      await mine;
    } else await run();
  }
}

// ---- the document ------------------------------------------------------------------

const WORDS = 450;
const sectionsOf = (n: number): OutlineSection[] =>
  Array.from({ length: n }, (_, i) => ({
    id: `s${i + 1}`,
    heading: `Part ${i + 1} of the protocol`,
    goal: `Explain how part ${i + 1} works and why it matters for connection security.`,
    keyPoints: ["handshake messages", "key schedule", "forward secrecy", "certificate checks"],
    queries: [`tls 1.3 part ${i + 1}`],
    visual: "none",
    words: WORDS,
    notes: "Lean on the RFC and vendor docs; connect to the previous section.",
    terms: ["TLS"],
  }));

const OUTLINE_JSON = {
  title: "TLS 1.3 in depth",
  subtitle: "How the handshake keeps the web private",
  audience: "developers",
  style: "guide",
  glossary: [{ term: "TLS", definition: "Transport Layer Security." }],
  sections: sectionsOf(8),
};

const SOURCE_TEXT = "TLS 1.3 removed RSA key exchange and requires forward secrecy for every connection. The handshake finishes in one round trip. ".repeat(13);
const completionTokens = (words: number) => Math.round(words * 1.5) + 60;
const promptTokens = (messages: Message[]) => Math.ceil(messages.reduce((n, m) => n + m.content.length, 0) / 3.5);
const body = (id: string) => `${id} explains the handshake and key schedule in detail [W1].\n<!--summary: ${id} covers one part of the protocol. It builds on the part before.-->`;

type Result = { tokens: number; calls: number; rateLimited: number; wallMs: number };

// ---- OLD arm: full outline + all summaries + 6 full sources, same top models ----------

async function oldFlow(): Promise<Result> {
  const clock = new VClock();
  const sim = new Sim(clock);
  const outline: Outline = { title: OUTLINE_JSON.title, subtitle: OUTLINE_JSON.subtitle, audience: "developers", style: "guide", sections: sectionsOf(8) };
  const candidates = ["groq:openai/gpt-oss-120b", "ollama:gpt-oss:120b", "nvidia:nvidia/nemotron-3-ultra-550b-a55b"];
  const summaries: Array<{ heading: string; summary: string }> = [];
  const sources = Array.from({ length: 6 }, (_, i) => `[W${i + 1}] Source ${i + 1} - https://example.com/${i}\n${SOURCE_TEXT.slice(0, 1_500)}`).join("\n\n");
  const writeOne = async (os: OutlineSection, i: number) => {
    const base = sectionMessages({ preamble: "", outline, glossary: [], section: os, context: null, validTags: ["W1", "W2", "W3", "W4", "W5", "W6"] });
    // What the old prompt added: the whole plan, every running summary and the full source excerpts.
    const plan = outline.sections.map((s, j) => `§${j + 1} ${s.heading} - ${s.goal}`).join("\n");
    const done = summaries.map((s) => `- ${s.heading}: ${s.summary}`).join("\n");
    const messages: Message[] = [...base, { role: "system", content: `Outline:\n${plan}\n\nAlready written (do not repeat):\n${done}\n\n<web_results>\n${sources}\n</web_results>` }];
    const pt = promptTokens(messages);
    let ok = false;
    for (const m of candidates) {
      try {
        await sim.call(m, pt, completionTokens(os.words));
        ok = true;
        break;
      } catch {
        /* the router moves on to the next candidate */
      }
    }
    if (!ok) throw new Error("section failed");
    summaries.push({ heading: os.heading, summary: `${os.heading} covers one part of the protocol. It builds on the part before.` });
    void i;
  };
  const queue = [...outline.sections];
  const lane = async () => {
    for (let os = queue.shift(); os; os = queue.shift()) await writeOne(os, 0);
  };
  const start = clock.now();
  await clock.drive(
    (async () => {
      await Promise.all([lane(), lane()]); // 2 per document
      await sim.call("groq:openai/gpt-oss-20b", 700, 400); // takeaways
    })(),
  );
  return { tokens: sim.tokens, calls: sim.calls, rateLimited: sim.rateLimited, wallMs: clock.now() - start };
}

// ---- NEW arm: the real pipeline with the dispatcher --------------------------------------

async function newFlow(): Promise<Result & { sections: number; status: string }> {
  const clock = new VClock();
  const sim = new Sim(clock);
  const store = memoryStore();
  const doc = await store.create({ userId: randomUUID(), conversationId: null, prompt: "Write a guide to TLS 1.3", options: { length: "standard", web: true, kb: false } });
  const WRITERS = ["groq:openai/gpt-oss-20b", "nvidia:nvidia/nemotron-3.5-lightning-30b-a3b", "ollama:gpt-oss:20b"];
  const deps: DocDeps = {
    store,
    ask: async (model, messages, opts) => {
      if (opts.purpose === "doc-outline") return JSON.stringify(OUTLINE_JSON);
      await sim.call(model, promptTokens(messages), 400);
      return JSON.stringify({ takeaways: ["One.", "Two.", "Three."], abstract: "An abstract.", fixes: [] });
    },
    runChat: async (cands, messages, _signal, hooks, _auto, opts) => {
      const model = cands[0];
      try {
        await sim.call(model, promptTokens(messages), completionTokens(WORDS));
      } catch (e) {
        throw new ChatFailure("all_models_failed", (e as Error).message, true);
      }
      hooks.onModel(model, 1);
      hooks.onDelta(body(/Write §(\d+)/.exec(messages[messages.length - 1].content)?.[1] ? `s${/Write §(\d+)/.exec(messages[messages.length - 1].content)![1]}` : "s"));
      void opts;
      return { model, promptTokens: null, completionTokens: null, finishReason: "stop" };
    },
    candidates: async () => WRITERS,
    outlineModels: async () => ["groq:openai/gpt-oss-120b"],
    finishModels: async () => ["groq:openai/gpt-oss-120b"],
    webSearch: async (q) => Array.from({ length: 4 }, (_, i) => ({ title: `R${i} ${q}`, url: `https://example.com/${encodeURIComponent(q)}/${i}`, content: SOURCE_TEXT, full: SOURCE_TEXT })),
    webFetch: async () => null,
    images: async () => [],
    retrieve: async () => [],
    attachments: async () => ({ items: [], failed: [] }),
    linkMessage: async () => {},
    limits: { ...DEFAULT_LIMITS, staggerMs: 0 },
    slots: new Semaphore(6),
    poolDeps: { now: clock.now, sleep: (ms) => clock.sleep(ms), headroom: (m, t) => (sim.headroom(m, t) ? { ok: true } : { ok: false, waitMs: 2_000 }) },
  };
  const job = registerJob(doc, "pipeline");
  const start = clock.now();
  await clock.drive(runPipeline(job, "full", deps));
  finishJob(job);
  const saved = (await store.get(doc.userId, doc.id))!;
  // The planner call (outline) is part of the new flow's cost; the old arm excludes planning, so subtract it for a like-for-like comparison.
  return { tokens: sim.tokens, calls: sim.calls, rateLimited: sim.rateLimited, wallMs: clock.now() - start, sections: saved.sections.filter((s) => s.status === "done").length, status: saved.status };
}

test("simulation: planner -> writers -> editor uses far fewer tokens and no 429s on an 8-section doc", async () => {
  const before = await oldFlow();
  const after = await newFlow();
  const pct = (a: number, b: number) => Math.round((1 - a / b) * 100);
  console.log(
    `DOC SIM (8 sections)\n  old: tokens=${before.tokens} calls=${before.calls} 429s=${before.rateLimited} wall=${Math.round(before.wallMs / 1000)}s\n  new: tokens=${after.tokens} calls=${after.calls} 429s=${after.rateLimited} wall=${Math.round(after.wallMs / 1000)}s\n  tokens saved: ${pct(after.tokens, before.tokens)}%`,
  );
  assert.equal(after.status, "done");
  assert.equal(after.sections, 8 + 2);
  assert.ok(after.tokens <= before.tokens * 0.6, `expected >=40% fewer tokens: ${after.tokens} vs ${before.tokens}`);
  assert.ok(after.rateLimited <= 1, `new flow 429s: ${after.rateLimited}`);
  assert.ok(before.rateLimited > after.rateLimited, "the old flow should be rate limited in this scenario");
});

test("simulation: a 429 moves the section to another provider instead of retrying the same one", async () => {
  const clock = new VClock();
  const { WriterPool } = await import("../src/docs/dispatch.js");
  const pool = new WriterPool(["groq:a", "nvidia:b", "ollama:c"], { perProvider: 2 }, { now: clock.now, sleep: (ms) => clock.sleep(ms), headroom: () => ({ ok: true }) });
  const seen: string[] = [];
  const ctl = new AbortController();
  let out: { model: string } | undefined;
  await clock.drive(
    pool
      .run(100, async (model) => {
        seen.push(model);
        if (model === "groq:a" || model === "nvidia:b") throw new UpstreamError(429, "rate limited");
        return "ok";
      }, ctl.signal)
      .then((r) => (out = r)),
  );
  assert.deepEqual(seen, ["groq:a", "nvidia:b", "ollama:c"]);
  assert.equal(out!.model, "ollama:c");
});

test("simulation: concurrency per provider is bounded and load spreads across providers", async () => {
  const clock = new VClock();
  const { WriterPool } = await import("../src/docs/dispatch.js");
  const pool = new WriterPool(["groq:a", "nvidia:b", "ollama:c"], { perProvider: 2 }, { now: clock.now, sleep: (ms) => clock.sleep(ms), headroom: () => ({ ok: true }) });
  const live = new Map<string, number>();
  const peak = new Map<string, number>();
  const used = new Map<string, number>();
  const ctl = new AbortController();
  await clock.drive(
    Promise.all(
      Array.from({ length: 9 }, () =>
        pool.run(100, async (model) => {
          const p = model.split(":")[0];
          live.set(p, (live.get(p) ?? 0) + 1);
          peak.set(p, Math.max(peak.get(p) ?? 0, live.get(p)!));
          used.set(p, (used.get(p) ?? 0) + 1);
          await clock.sleep(1_000);
          live.set(p, live.get(p)! - 1);
        }, ctl.signal),
      ),
    ),
  );
  for (const v of peak.values()) assert.ok(v <= 2);
  assert.equal(used.size, 3);
  for (const v of used.values()) assert.ok(v >= 2);
});
