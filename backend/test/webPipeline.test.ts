import assert from "node:assert/strict";
import { test } from "node:test";
import { engineQuery, parseBingRss, parseBraveHtml, parseDuckDuckGo, parseDuckDuckGoLite, unwrapRedirect } from "../src/web/general.js";
import { mergeCandidates, mmr, blendSemantic } from "../src/web/rank.js";
import { heuristicQueries, needsModel, queryLang } from "../src/web/plan.js";
import { searchCacheKey } from "../src/web/cacheStore.js";
import { collect, hedgedChain, researchCacheKey } from "../src/web/pipeline.js";
import { breaker, callProvider, CACHE_TTL_MS, PROVIDERS, ProviderError, type CallOutcome, type Provider } from "../src/web/providers.js";
import { splitPassages, stem, stripMarkup } from "../src/web/passages.js";
import { recordOutcome, resetWebStats, webStats } from "../src/web/stats.js";
import { markQuota, resetQuota } from "../src/llm/quota.js";
import { OLLAMA_WEB_ID } from "../src/web/ollama.js";
import type { Candidate, SearchCtx } from "../src/web/types.js";

const cand = (source: string, url: string, title: string, rank: number, extra: Partial<Candidate> = {}): Candidate => ({ source, url, title, snippet: title, rank, ...extra });

// ---- merged:0 (production bug) ------------------------------------------------------

const ADA = [
  cand("wikipedia", "https://en.wikipedia.org/wiki/Ada_Lovelace", "Ada Lovelace - Wikipedia", 0, {
    text: "Augusta Ada King, Countess of Lovelace was an English mathematician and writer chiefly known for her work on Charles Babbage's proposed mechanical general-purpose computer, the Analytical Engine. She was the first to recognise that the machine had applications beyond pure calculation, and her contributions to computing include the first published algorithm.",
  }),
  cand("wikipedia", "https://en.wikipedia.org/wiki/Analytical_engine", "Analytical engine - Wikipedia", 1, {
    text: "The analytical engine was a proposed digital mechanical general-purpose computer designed by Charles Babbage. Ada Lovelace wrote the first program for it; her notes describe contributions to computing that later inspired Alan Turing.",
  }),
  cand("wikipedia", "https://en.wikipedia.org/wiki/Matt_Lucas", "Matt Lucas - Wikipedia", 2, { text: "Matthew Richard Lucas is an English comedian, actor and television presenter." }),
];

test("merged:0 reproduced: a Hinglish question glued to the English query diluted every topical hit below the cut", () => {
  const question = "ada lovelace kaun thi aur usne computer ke liye kya kiya, detail mein batao";
  const queries = ["Ada Lovelace contributions computing"];
  // The old pipeline measured relevance against queries + question as one string.
  const old = mergeCandidates([ADA], "evergreen", [...queries, question].join(" "));
  assert.equal(old.length, 0, "the old focus string drops everything (prod: wikipedia:3 merged:0)");
  // Now each phrasing is measured on its own: the query matches, the off-topic page still goes.
  const fixed = mergeCandidates([ADA], "evergreen", { queries, question });
  assert.deepEqual(fixed.map((m) => m.url), ["https://en.wikipedia.org/wiki/Ada_Lovelace", "https://en.wikipedia.org/wiki/Analytical_engine"]);
});

test("a long code question no longer filters out the StackOverflow answer the keyword query found", () => {
  const so = cand("stackexchange", "https://stackoverflow.com/q/1", "Execution failed for task ':app:checkDebugAarMetadata'", 0, {
    text: "Question: Execution failed for task ':app:checkDebugAarMetadata'\n\nAccepted answer: raise compileSdkVersion to 34 in android/app/build.gradle and run flutter clean.",
  });
  const question = "my flutter app fails with 'Execution failed for task :app:checkDebugAarMetadata' after upgrading, I tried flutter clean and it did not help, what else";
  const other = cand("stackexchange", "https://stackoverflow.com/q/2", "How to center a div", 1, { text: "Question: How to center a div\n\nAccepted answer: use flexbox." });
  const out = mergeCandidates([[so, other]], "evergreen", { queries: ["flutter checkDebugAarMetadata execution failed"], question });
  assert.deepEqual(out.map((m) => m.url), ["https://stackoverflow.com/q/1"]);
});

test("only weakly related topical hits: the closest few are kept instead of nothing", () => {
  const out = mergeCandidates([[cand("wikipedia", "https://en.wikipedia.org/wiki/Nginx", "Nginx - Wikipedia", 0, { text: "Nginx is a web server that can also be used as a reverse proxy." })]], "evergreen", {
    queries: ["nginx reverse proxy node app websocket timeout"],
  });
  assert.equal(out.length, 1);
});

test("dedupe by canonical URL across engines merges sources and keeps the best text and title", () => {
  const merged = mergeCandidates(
    [
      [cand("duckduckgo", "https://www.example.com/guide/?utm_source=ddg", "Guide to X", 0)],
      [cand("brave", "http://example.com/guide#intro", "Guide to X | Example", 1, { text: "long body ".repeat(60), published: "2026-01-02" })],
      [cand("ollama", "https://example.com/guide/", "https://example.com/guide/", 0)],
    ],
    "recent",
    { queries: ["guide to x"] },
  );
  assert.equal(merged.length, 1);
  assert.equal(merged[0].sources.size, 3);
  assert.equal(merged[0].title, "Guide to X");
  assert.ok((merged[0].text?.length ?? 0) > 400);
  assert.equal(merged[0].published, "2026-01-02");
});

// ---- ranking ------------------------------------------------------------------------

test("MMR demotes near-duplicate pages below a different angle", () => {
  const items = [
    { url: "https://a.com/1", score: 1, title: "Install Rust on Ubuntu with rustup", snippet: "Install Rust on Ubuntu using rustup in three steps" },
    { url: "https://b.com/1", score: 0.95, title: "Install Rust on Ubuntu with rustup", snippet: "Install Rust on Ubuntu using rustup in three steps" },
    { url: "https://c.com/1", score: 0.9, title: "Rust toolchains explained: stable, beta, nightly", snippet: "How rustup manages toolchains and components" },
  ];
  assert.deepEqual(mmr(items, 2).map((i) => i.url), ["https://a.com/1", "https://c.com/1"]);
});

test("semantic blend reorders by embedding similarity when available, and is a no-op without it", () => {
  const items = () => [
    { url: "u1", score: 0.6 },
    { url: "u2", score: 0.55 },
  ];
  assert.deepEqual(blendSemantic(items(), new Map()).map((i) => i.url), ["u1", "u2"]);
  assert.deepEqual(blendSemantic(items(), new Map([["u1", 0.2], ["u2", 0.9]]), 0.4).map((i) => i.url), ["u2", "u1"]);
});

// ---- planner rules --------------------------------------------------------------------

test("rule-based planning: answer-format instructions are not search terms, Devanagari is detected", () => {
  assert.deepEqual(heuristicQueries("explain how DNS resolution works in detail with examples"), ["explain how DNS resolution works"]);
  assert.deepEqual(heuristicQueries("ada lovelace kaun thi, detail mein batao"), ["ada lovelace kaun thi"]);
  assert.equal(queryLang("भारत के पहले प्रधानमंत्री कौन थे"), "hi");
  assert.equal(queryLang("who was the first prime minister of India"), undefined);
  // Simple standalone questions never pay for a planner model call.
  assert.equal(needsModel("who was the first prime minister of India", {}), false);
  assert.equal(needsModel("and its price?", { previousUser: "tell me about the pixel 10" }), true);
});

test("stemming joins word forms that used to miss each other", () => {
  assert.equal(stem("computer"), stem("computing"));
  assert.equal(stem("contributions"), stem("contributed"));
  assert.equal(stem("नमस्ते"), "नमस्ते");
});

// ---- cache keys and TTLs ----------------------------------------------------------------

test("cache keys normalize the query and separate freshness and language; TTL grows with stability", () => {
  assert.equal(searchCacheKey("duckduckgo", "recent", "Node.js LTS?"), searchCacheKey("duckduckgo", "recent", "  node js   lts "));
  assert.notEqual(searchCacheKey("wikipedia", "evergreen", "x y", "hi"), searchCacheKey("wikipedia", "evergreen", "x y"));
  const a = researchCacheKey({ queries: ['"Ada Lovelace" contributions'], fresh: "evergreen" }, undefined, 5, 3);
  assert.equal(a, researchCacheKey({ queries: ["ada lovelace CONTRIBUTIONS"], fresh: "evergreen" }, undefined, 5, 3));
  assert.notEqual(a, researchCacheKey({ queries: ["ada lovelace contributions"], fresh: "breaking" }, undefined, 5, 3));
  assert.ok(CACHE_TTL_MS.breaking < CACHE_TTL_MS.recent && CACHE_TTL_MS.recent < CACHE_TTL_MS.evergreen);
});

// ---- hedging, early return, breaker and quota skips ------------------------------------------

let seq = 0;
const fake = (o: Partial<Provider> & { delay?: number; hits?: number; fail?: ProviderError; calls?: { n: number } }): Provider => {
  const name = o.name ?? `fake${++seq}`;
  return {
    name,
    role: o.role ?? "web",
    intents: o.intents ?? "any",
    timeoutMs: 5_000,
    enabled: o.enabled ?? (() => true),
    async search(query) {
      if (o.calls) o.calls.n++;
      await new Promise((r) => setTimeout(r, o.delay ?? 0));
      if (o.fail) throw o.fail;
      return Array.from({ length: o.hits ?? 6 }, (_, i) => cand(o.role === "secondary" ? "wikipedia" : "duckduckgo", `https://${name}.test/${i}`, `${query} result ${i}`, i, i === 0 ? { text: `${query} `.repeat(80) } : {}));
    },
  };
};
const ctx = (): SearchCtx => ({ fresh: "evergreen", limit: 8 });
const tracker = (out: CallOutcome[]) => (p: Promise<CallOutcome>) => p.then((o) => (out.push(o), o));

test("hedged chain: a good first answer means the next engine is never asked", async () => {
  const second = { n: 0 };
  const out: CallOutcome[] = [];
  await hedgedChain([fake({ delay: 5 }), fake({ calls: second })], "hedge good q", ctx(), tracker(out), 200);
  assert.equal(second.n, 0);
  assert.equal(out.length, 1);
});

test("hedged chain: a slow engine gets a hedge, a failing one is skipped at once", async () => {
  const out: CallOutcome[] = [];
  const t = Date.now();
  await hedgedChain([fake({ delay: 400 }), fake({ delay: 5 })], "hedge slow q", ctx(), tracker(out), 50);
  assert.ok(Date.now() - t < 300, "resolved by the hedge, not the slow engine");
  const out2: CallOutcome[] = [];
  await hedgedChain([fake({ fail: new ProviderError("HTTP 500", 500) }), fake({})], "hedge fail q", ctx(), tracker(out2), 10_000);
  assert.deepEqual(out2.map((o) => !!o.error), [true, false]);
});

test("collect returns early once the web engines answered, without waiting for slow topical sources", async () => {
  const plan = { queries: ["early return query"], fresh: "evergreen" as const, intents: ["encyclopedic" as const], via: "heuristic" as const };
  const t = Date.now();
  const r = await collect(plan, undefined, { want: 3, focus: { queries: plan.queries }, graceMs: 100, providers: [fake({ delay: 10 }), fake({ role: "secondary", intents: ["encyclopedic"], delay: 3_000 })] });
  assert.ok(Date.now() - t < 1_000, `took ${Date.now() - t}ms`);
  assert.equal(r.early, true);
  assert.equal(r.outcomes.length, 1);
});

test("collect waits for topical sources when no web engine is available", async () => {
  const plan = { queries: ["no web engines query"], fresh: "evergreen" as const, intents: ["encyclopedic" as const], via: "heuristic" as const };
  const r = await collect(plan, undefined, { want: 3, focus: { queries: plan.queries }, graceMs: 50, providers: [fake({ enabled: () => false }), fake({ role: "secondary", intents: ["encyclopedic"], delay: 150 })] });
  assert.equal(r.outcomes.length, 1);
  assert.equal(r.outcomes[0].candidates.length, 6);
});

test("an engine that blocks us (429 with a long cooldown) opens its circuit at once and is not called again", async () => {
  const calls = { n: 0 };
  const p = fake({ calls, fail: new ProviderError("bot check", 429, 10 * 60_000) });
  const first = await callProvider(p, "blocked engine q1", ctx());
  assert.equal(first.error, "http_429");
  assert.equal(breaker.state(p.name), "open");
  const second = await callProvider(p, "blocked engine q2", ctx());
  assert.equal(second.skipped, "circuit");
  assert.equal(calls.n, 1);
  // collect() does not even schedule it.
  const r = await collect({ queries: ["blocked engine q3"], fresh: "evergreen", intents: ["encyclopedic"], via: "heuristic" }, undefined, { want: 1, focus: "", providers: [p, fake({})] });
  assert.equal(calls.n, 1);
  assert.ok(r.outcomes.every((o) => o.provider !== p.name));
  breaker.success(p.name);
});

test("Ollama's web search is never asked while its quota is exhausted", () => {
  const ollama = PROVIDERS.find((p) => p.name === "ollama")!;
  markQuota(OLLAMA_WEB_ID, { kind: "quota_exhausted", window: "month", scope: "provider", untilMs: Date.now() + 86_400_000 });
  try {
    assert.equal(ollama.enabled(), false);
    // The keyless engines come first in the chain either way.
    const web = PROVIDERS.filter((p) => p.role === "web").map((p) => p.name);
    assert.ok(web.indexOf("duckduckgo") < web.indexOf("ollama"));
  } finally {
    resetQuota();
  }
});

// ---- engine parsers --------------------------------------------------------------------

test("DuckDuckGo HTML: organic results only, redirect links unwrapped", () => {
  const html = `
<div class="result results_links results_links_deep result--ad"><a rel="nofollow" class="result__a" href="https://duckduckgo.com/y.js?ad=1">Buy now</a><a class="result__snippet">ad</a></div>
<div class="result results_links results_links_deep web-result"><h2><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fdocs.rs%2Ftokio&amp;rut=x">Tokio &amp; async</a></h2>
<a class="result__snippet" href="x">The <b>Tokio</b> runtime docs.</a></div>
<div class="result results_links web-result"><a rel="nofollow" class="result__a" href="https://tokio.rs/">Tokio</a><a class="result__snippet" href="x">An asynchronous runtime.</a></div>`;
  const out = parseDuckDuckGo(html);
  assert.deepEqual(out.map((c) => c.url), ["https://docs.rs/tokio", "https://tokio.rs/"]);
  assert.equal(out[0].title, "Tokio & async");
  assert.equal(out[0].snippet, "The Tokio runtime docs.");
  assert.deepEqual(out.map((c) => c.rank), [0, 1]);
});

test("DuckDuckGo lite, Brave HTML and Bing News RSS parsers", () => {
  const lite = `<tr><td><a rel="nofollow" href="https://betterstack.com/nginx" class='result-link'>Nginx as a reverse proxy</a></td></tr>
<tr><td>&nbsp;</td><td class='result-snippet'>Set up a <b>reverse proxy</b> for Node.</td></tr>
<tr><td><a rel="nofollow" href="https://nginx.org/" class='result-link'>nginx</a></td></tr>`;
  assert.deepEqual(parseDuckDuckGoLite(lite).map((c) => [c.url, c.snippet]), [["https://betterstack.com/nginx", "Set up a reverse proxy for Node."], ["https://nginx.org/", ""]]);

  const brave = `<div class="snippet svelte-x" data-pos="0" data-type="web"><a href="https://blog.logrocket.com/nginx/" class="l1"><div class="title search-snippet-title line-clamp-1 svelte-y" title="Use Nginx as a reverse proxy">Use Nginx as a reverse proxy</div></a><div class="generic-snippet"><div class="content desktop-default-regular t-primary"><!---->4 June 2024 - As a <strong>reverse proxy</strong>, Nginx intercepts requests.<!----></div></div></div>
<div class="snippet svelte-x" data-type="web"><a href="https://search.brave.com/goggles">Goggles</a><div class="search-snippet-title">Goggles</div></div>`;
  const b = parseBraveHtml(brave);
  assert.equal(b.length, 1);
  assert.equal(b[0].title, "Use Nginx as a reverse proxy");
  assert.equal(b[0].snippet, "As a reverse proxy, Nginx intercepts requests.");
  assert.equal(b[0].published, "2024-06-04");

  const rss = `<rss><channel><item><title>Starship flies</title><link>http://www.bing.com/news/apiclick.aspx?ref=FexRss&amp;url=https%3a%2f%2fwww.space.com%2fstarship&amp;c=1</link><description>It flew.</description><pubDate>Mon, 12 Oct 2026 16:16:00 GMT</pubDate></item></channel></rss>`;
  const n = parseBingRss(rss, "bingnews");
  assert.equal(n[0].url, "https://www.space.com/starship");
  assert.equal(n[0].published, "2026-10-12");
  assert.equal(unwrapRedirect("https://example.com/a"), "https://example.com/a");
});

test("engine queries drop punctuation DuckDuckGo rejects but keep code symbols", () => {
  assert.equal(engineQuery(`TypeError: Cannot read properties of undefined (reading 'map')`), "TypeError Cannot read properties of undefined reading map");
  assert.equal(engineQuery("c++ vs c# .net"), "c++ vs c# .net");
});

// ---- extraction ----------------------------------------------------------------------

test("passage extraction drops menus, share bars and images, and keeps link text", () => {
  const md = [
    "Home\nProducts\nPricing\nBlog\nCareers",
    "Share this article",
    "![hero](https://x.test/a.png)",
    "The [Analytical Engine](https://en.wikipedia.org/wiki/Analytical_engine) was designed by **Charles Babbage** and described by Ada Lovelace in her notes of 1843.",
    "Advertisement",
  ].join("\n\n");
  const ps = splitPassages(md);
  assert.equal(ps.length, 1);
  assert.equal(ps[0], "The Analytical Engine was designed by Charles Babbage and described by Ada Lovelace in her notes of 1843.");
  assert.equal(stripMarkup("```js\nconst [a](b) = 1\n```"), "```js\nconst [a](b) = 1\n```");
});

// ---- observability ----------------------------------------------------------------------

test("web stats track latency, cache hits, empty and error rates per provider", () => {
  resetWebStats();
  recordOutcome({ provider: "p", candidates: [1, 2], ms: 100 });
  recordOutcome({ provider: "p", candidates: [], ms: 300 });
  recordOutcome({ provider: "p", candidates: [1], ms: 0, cached: true });
  recordOutcome({ provider: "p", candidates: [], ms: 50, error: "http_429" });
  const s = webStats().providers.find((x) => x.provider === "p")!;
  assert.equal(s.calls, 3);
  assert.equal(s.emptyRate, 0.5);
  assert.equal(s.errorRate, 0.333);
  assert.equal(s.cacheHitRate, 0.25);
  assert.equal(s.p50Ms, 300);
  assert.equal(s.lastError, "http_429");
});
