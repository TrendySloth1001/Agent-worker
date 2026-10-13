import { test, afterEach } from "node:test";
import assert from "node:assert/strict";
import sharp from "sharp";
import { detectToolCall, ToolCallGuard } from "../src/llm/toolCall.js";
import { identificationMessage, identifyImage, identifyModels, imageWantsWeb, parseIdentification, searchIdentified, type AskFn } from "../src/context/imageWeb.js";
import { IMAGE_MAX_EDGE, IMAGE_JPEG_QUALITY, VISION_MODELS } from "../src/llm/vision.js";
import { asksForWidget, buildSystemPrompt } from "../src/prompts/system.js";
import { runChat, type RunHooks } from "../src/llm/router.js";
import { toJpeg } from "../src/files/media.js";
import { clearCooldown } from "../src/models.js";
import { resetQuota } from "../src/llm/quota.js";
import { resetBudget } from "../src/llm/budget.js";
import { UpstreamError, type StreamHandle, type StreamOptions, type StreamUsage } from "../src/providers.js";

afterEach(() => {
  resetQuota();
  resetBudget();
  for (const id of VISION_MODELS) clearCooldown(id);
});

// ---- tool-call detection --------------------------------------------------------

/** The exact reply production showed the user (nemotron omni reasoning, Circle to Search). */
const PROD_REPLY = '```json\n{ "type": "websearch", "query": "Khuda hi jaaye Ramz Rai" }\n```';

test("tool call: the production reply is recognised with its query", () => {
  const c = detectToolCall(PROD_REPLY);
  assert.ok(c);
  assert.equal(c.query, "Khuda hi jaaye Ramz Rai");
});

test("tool call: the common shapes are all recognised", () => {
  const cases: Array<[string, string | null]> = [
    ['{"type":"websearch","query":"sony wh-1000xm5 price"}', "sony wh-1000xm5 price"],
    ['{"tool": "web_search", "query": "eiffel tower height"}', "eiffel tower height"],
    ['{"tool":"search","args":{"q":"red panda"}}', "red panda"],
    ['{"name": "search", "arguments": {"query": "what is this plant"}}', "what is this plant"],
    ['{"name":"web_search","arguments":"{\\"query\\":\\"monstera deliciosa\\"}"}', "monstera deliciosa"],
    ['{"type":"function","function":{"name":"web_search","arguments":"{\\"query\\":\\"tesla model y\\"}"}}', "tesla model y"],
    ['<tool_call>\n{"name": "web_search", "arguments": {"query": "Ramz Rai song"}}\n</tool_call>', "Ramz Rai song"],
    ['<tool_call>{"name":"search","arguments":{"query":"x"}}', "x"],
    ['search("Khuda hi jaaye lyrics")', "Khuda hi jaaye lyrics"],
    ["web_search(query='nothing phone 3 price')", "nothing phone 3 price"],
    ['```tool_code\nsearch("nothing phone 3")\n```', "nothing phone 3"],
    ['```\n{"type": "websearch", "query": "q"}\n```', "q"],
  ];
  for (const [reply, query] of cases) {
    const c = detectToolCall(reply);
    assert.ok(c, reply);
    assert.equal(c.query, query, reply);
  }
});

test("tool call: ordinary answers are never mistaken for one", () => {
  const prose = [
    "That's a pair of Sony WH-1000XM5 headphones [W1].",
    "Search results suggest it's a Monstera.",
    '```chart\n{"type":"bar","title":"Sales","x":["a"],"series":[{"name":"s","data":[1]}]}\n```',
    '```json\n{"name": "my-app", "version": "1.0.0"}\n```',
    "{{image:Eiffel Tower at night|The tower lit up}}\nIt's the Eiffel Tower.",
    "```email\nTo: a@b.c\nSubject: Hi\n\nHello\n```",
    "```python\nimport requests\nprint(requests.get('x'))\n```",
    "[Sony](https://sony.com) makes it.",
  ];
  for (const p of prose) assert.equal(detectToolCall(p), null, p);
});

function streamThrough(g: ToolCallGuard, reply: string, size: number): string {
  let out = "";
  for (let i = 0; i < reply.length; i += size) out += g.push(reply.slice(i, i + size));
  return out + g.flush();
}

test("guard: the production reply streamed in small chunks shows nothing and reports the call", () => {
  for (const size of [1, 3, 7, 50]) {
    const g = new ToolCallGuard();
    assert.equal(streamThrough(g, PROD_REPLY, size), "", `chunk ${size}`);
    assert.equal(g.call()?.query, "Khuda hi jaaye Ramz Rai");
  }
  for (const reply of ['{"tool":"search","query":"a b"}', '<tool_call>{"name":"search","arguments":{"query":"a b"}}</tool_call>', 'search("a b")']) {
    const g = new ToolCallGuard();
    assert.equal(streamThrough(g, reply, 2), "", reply);
    assert.equal(g.call()?.query, "a b", reply);
  }
});

test("guard: prose, widgets and code pass through unchanged", () => {
  const replies = [
    "That's a **Sony WH-1000XM5** [W1].",
    "Searching isn't needed: it's a cat.",
    "{{image:Red panda}}\nA red panda.",
    '```chart\n{"type":"bar","x":["a"],"series":[]}\n```\nDone.',
    "```bash\nnpm i\n```",
    "Google Pixel 9 Pro, by the look of it.",
    "S",
  ];
  for (const r of replies) {
    for (const size of [1, 4, 100]) {
      const g = new ToolCallGuard();
      assert.equal(streamThrough(g, r, size), r, `${r} @${size}`);
      assert.equal(g.call(), null);
    }
  }
});

test("guard: a tool call followed by an answer keeps only the answer", () => {
  const g = new ToolCallGuard();
  const out = streamThrough(g, '{"type":"websearch","query":"x"}\n\nIt is a Monstera deliciosa.', 5);
  assert.equal(out, "It is a Monstera deliciosa.");
  assert.equal(g.call()?.query, "x");
});

// ---- when an image turn goes to the web ---------------------------------------------

test("imageWantsWeb: explicit asks search; WEB off never; plain image questions do not", () => {
  const on = (text: string, webMode: "auto" | "on" | "off" = "on") => imageWantsWeb({ text, webMode, hasImage: true });
  assert.equal(on("What is this? Search the web for it."), true);
  assert.equal(on("what is this", "auto"), true);
  assert.equal(on("identify this plant", "auto"), true);
  assert.equal(on("where can I buy these shoes?", "auto"), true);
  assert.equal(on("how much does this cost"), true);
  assert.equal(on("", "on"), true);
  assert.equal(on("", "auto"), false);
  assert.equal(on("What is this? Search the web for it.", "off"), false);
  assert.equal(on("translate the text in this screenshot"), false);
  assert.equal(on("fix the bug in this code", "auto"), false);
  assert.equal(imageWantsWeb({ text: "what is this", webMode: "on", hasImage: false }), false);
});

// ---- step A: identification ------------------------------------------------------------

const ID_JSON = '{"subject":"Sony WH-1000XM5","kind":"product","visible_text":"SONY WH-1000XM5","description":"Black over-ear headphones.","queries":["Sony WH-1000XM5","Sony WH-1000XM5 price"]}';

test("parseIdentification: plain, fenced, with thinking, and with a missing query list", () => {
  for (const raw of [ID_JSON, "```json\n" + ID_JSON + "\n```", "<think>looks like headphones</think>" + ID_JSON, "Here you go: " + ID_JSON + " Hope it helps"]) {
    const p = parseIdentification(raw);
    assert.ok(p, raw);
    assert.equal(p.subject, "Sony WH-1000XM5");
    assert.deepEqual(p.queries, ["Sony WH-1000XM5", "Sony WH-1000XM5 price"]);
  }
  const p = parseIdentification('{"subject":"Ramz Rai","visible_text":"Khuda hi jaaye"}');
  assert.deepEqual(p?.queries, ["Ramz Rai Khuda hi jaaye"]);
  assert.equal(parseIdentification("Sure! The image shows headphones."), null);
});

test("identifyModels: fast models only, reasoning/omni dropped while a fast one is left", () => {
  assert.deepEqual(identifyModels(VISION_MODELS), ["groq:qwen/qwen3.8-27b", "nvidia:meta/llama-3.2-11b-vision-instruct", "openrouter:google/gemma-4-31b-it:free"]);
  assert.deepEqual(identifyModels(["nvidia:nvidia/nemotron-3-nano-omni-30b-a3b-reasoning"]), ["nvidia:nvidia/nemotron-3-nano-omni-30b-a3b-reasoning"]);
});

test("identifyImage: one small call with the screen text as a hint; falls through a failing model", async () => {
  const seen: Array<{ model: string; content: string; images: number; maxTokens: number }> = [];
  const ask: AskFn = async (model, messages, opts) => {
    seen.push({ model, content: messages.map((m) => m.content).join("\n"), images: messages.reduce((n, m) => n + (m.images?.length ?? 0), 0), maxTokens: opts.maxTokens });
    if (model === "groq:qwen/qwen3.8-27b") throw new UpstreamError(429, "Rate limit reached");
    return ID_JSON;
  };
  const r = await identifyImage({ image: "AAAA", question: "What is this? Search the web for it.", screenText: "Sony WH-1000XM5 | Amazon.in", models: identifyModels(VISION_MODELS), signal: new AbortController().signal, ask });
  assert.equal(r?.subject, "Sony WH-1000XM5");
  assert.equal(r?.model, "nvidia:meta/llama-3.2-11b-vision-instruct");
  assert.deepEqual(seen.map((s) => s.model), ["groq:qwen/qwen3.8-27b", "nvidia:meta/llama-3.2-11b-vision-instruct"]);
  assert.ok(seen[0].content.includes("Amazon.in"));
  assert.ok(seen[0].content.includes("ONLY one JSON object"));
  assert.equal(seen[0].images, 1);
  assert.ok(seen[0].maxTokens <= 400);
});

test("identifyImage: gives up within its time budget", async () => {
  const ask: AskFn = (_m, _msgs, opts) => new Promise((_, rej) => setTimeout(() => rej(new UpstreamError(0, "timeout")), opts.timeoutMs));
  const at = Date.now();
  const r = await identifyImage({ image: "AAAA", question: "what is this", models: ["a:1", "b:2", "c:3"], signal: new AbortController().signal, ask, modelMs: 200, totalMs: 1_900 });
  assert.equal(r, null);
  assert.ok(Date.now() - at < 1_500);
});

// ---- the whole image + web flow (fake vision and web) ---------------------------------

test("image + web flow: identify -> search the identified queries -> answer context names the subject", async () => {
  const ask: AskFn = async () => ID_JSON;
  const searched: string[][] = [];
  const signal = new AbortController().signal;
  const ident = await identifyImage({ image: "AAAA", question: "What is this? Search the web for it.", models: ["groq:qwen/qwen3.8-27b"], signal, ask });
  const r = await searchIdentified(
    ident,
    async ({ queries }) => {
      searched.push(queries);
      return [{ title: "Sony WH-1000XM5", url: "https://www.sony.com/wh-1000xm5", content: "Industry-leading noise cancelling headphones." }];
    },
    signal,
  );
  assert.deepEqual(searched, [["Sony WH-1000XM5", "Sony WH-1000XM5 price"]]);
  assert.equal(r.searched, true);
  assert.equal(r.results.length, 1);
  const note = identificationMessage(ident!);
  assert.match(note, /Subject: Sony WH-1000XM5/);
  assert.match(note, /\[W#\]/);
  // Nothing identified: nothing searched; a broken search is reported, not thrown.
  assert.deepEqual(await searchIdentified(null, async () => [], signal), { results: [], searched: false, failed: false });
  const broken = await searchIdentified(ident, async () => {
    throw new Error("down");
  }, signal);
  assert.equal(broken.failed, true);
});

// ---- vision ordering and the first-token timeout --------------------------------------

function hooks() {
  const out = { deltas: [] as string[], fallbacks: [] as string[] };
  const h: RunHooks = { onQueued() {}, onModel() {}, onDelta: (t) => void out.deltas.push(t), onReset() {}, onFallback: (f, t) => void out.fallbacks.push(`${f}->${t}`) };
  return { h, out };
}

/** A model that streams only hidden reasoning until it is aborted (or `afterMs`, then answers). */
function slowStream(scripts: Record<string, { afterMs?: number; text: string }>, calls: string[]) {
  return async (id: string, _m: unknown, opts: StreamOptions): Promise<StreamHandle> => {
    calls.push(id);
    const usage: StreamUsage = { promptTokens: 10, completionTokens: 5, finishReason: null, completed: false };
    const s = scripts[id];
    async function* tokens(): AsyncGenerator<string> {
      if (!s) throw new UpstreamError(500, "no script");
      yield "<think>";
      await new Promise<void>((resolve, reject) => {
        const t = setTimeout(resolve, s.afterMs ?? 0);
        opts.signal.addEventListener("abort", () => (clearTimeout(t), reject(new DOMException("aborted", "AbortError"))), { once: true });
      });
      yield "</think>" + s.text;
      usage.completed = true;
      usage.finishReason = "stop";
    }
    return { tokens: tokens(), usage };
  };
}

test("vision: a model silent past the first-token timeout gives way to the next", async () => {
  const calls: string[] = [];
  const { h, out } = hooks();
  const chain = ["nvidia:nvidia/nemotron-3-nano-omni-30b-a3b-reasoning", "nvidia:meta/llama-3.2-11b-vision-instruct"];
  const at = Date.now();
  const r = await runChat(chain, [{ role: "user", content: "what is this?", images: ["AAAA"] }], new AbortController().signal, h, true, {
    firstTokenMs: 80,
    stream: slowStream({ [chain[0]]: { afterMs: 5_000, text: "slow" }, [chain[1]]: { afterMs: 10, text: "Headphones." } }, calls) as never,
  });
  assert.equal(r.model, chain[1]);
  assert.equal(out.deltas.join(""), "Headphones.");
  assert.deepEqual(calls, chain);
  assert.ok(Date.now() - at < 2_000);
});

test("vision: the last model left is never cut off by the first-token timeout", async () => {
  const calls: string[] = [];
  const { h, out } = hooks();
  const r = await runChat(["nvidia:meta/llama-3.2-11b-vision-instruct"], [{ role: "user", content: "x", images: ["AAAA"] }], new AbortController().signal, h, true, {
    firstTokenMs: 30,
    stream: slowStream({ "nvidia:meta/llama-3.2-11b-vision-instruct": { afterMs: 150, text: "A cat." } }, calls) as never,
  });
  assert.equal(r.model, "nvidia:meta/llama-3.2-11b-vision-instruct");
  assert.equal(out.deltas.join(""), "A cat.");
});

// ---- compact prompt for image turns ----------------------------------------------------

test("compact prompt: image turns drop the widget catalogue but keep the citation and safety rules", () => {
  const full = buildSystemPrompt("default", undefined, new Date("2026-10-13"), { widgetExamples: false });
  const compact = buildSystemPrompt("default", undefined, new Date("2026-10-13"), { compact: true });
  assert.ok(full.length - compact.length > 4_000, `${full.length} -> ${compact.length}`);
  assert.ok(!compact.includes("\u0000"));
  assert.ok(!compact.includes("```quiz"));
  assert.match(compact, /Cite at sentence level/);
  assert.match(compact, /Never invent facts/);
  assert.equal(asksForWidget("make a chart of this"), true);
  assert.equal(asksForWidget("What is this? Search the web for it."), false);
});

// ---- downscale ------------------------------------------------------------------------

test("images are downscaled to the vision long edge and re-encoded as JPEG", async () => {
  const big = await sharp({ create: { width: 3000, height: 2000, channels: 3, background: "#3366aa" } }).png().toBuffer();
  const out = await toJpeg(big, IMAGE_MAX_EDGE, IMAGE_JPEG_QUALITY);
  assert.equal(Math.max(out.width, out.height), IMAGE_MAX_EDGE);
  assert.equal(out.width, 1024);
  assert.equal(out.height, 683);
  const meta = await sharp(out.data).metadata();
  assert.equal(meta.format, "jpeg");
  const small = await sharp({ create: { width: 400, height: 300, channels: 3, background: "#fff" } }).png().toBuffer();
  assert.equal((await toJpeg(small, IMAGE_MAX_EDGE, IMAGE_JPEG_QUALITY)).width, 400, "never enlarged");
});
