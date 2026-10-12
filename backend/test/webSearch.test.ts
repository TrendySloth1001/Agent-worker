import assert from "node:assert/strict";
import { test } from "node:test";
import { CircuitBreaker } from "../src/web/breaker.js";
import { TtlLru } from "../src/web/lru.js";
import { rankPassages, selectPassages, splitPassages, terms } from "../src/web/passages.js";
import { diversify, mergeCandidates } from "../src/web/rank.js";
import { authority, baseDomain, dedupeByUrl, normalizeUrl } from "../src/web/url.js";
import { dedupeQueries, detectIntents, heuristicQueries, parsePlan } from "../src/web/plan.js";

test("normalizeUrl strips tracking, www, fragments and trailing slashes", () => {
  assert.equal(normalizeUrl("http://www.Example.com/a/b/?utm_source=x&b=2&a=1#frag"), "https://example.com/a/b?a=1&b=2");
  assert.equal(normalizeUrl("https://example.com:443/path//x/"), "https://example.com/path/x");
  assert.equal(normalizeUrl("https://m.example.com/x/amp"), "https://example.com/x");
  assert.equal(normalizeUrl("https://arxiv.org/pdf/2401.01234v3.pdf"), "https://arxiv.org/abs/2401.01234");
  assert.equal(normalizeUrl("https://arxiv.org/abs/2401.01234v1"), "https://arxiv.org/abs/2401.01234");
  assert.equal(normalizeUrl("ftp://example.com/x"), null);
  assert.equal(normalizeUrl("not a url"), null);
});

test("dedupeByUrl keeps the first and merges duplicates", () => {
  const items = [
    { url: "https://www.site.com/post/?utm_campaign=a", n: 1, tags: ["a"] },
    { url: "http://site.com/post#top", n: 2, tags: ["b"] },
    { url: "https://other.com/post", n: 3, tags: ["c"] },
  ];
  const out = dedupeByUrl(items, (keep, drop) => keep.tags.push(...drop.tags));
  assert.deepEqual(out.map((i) => i.n), [1, 3]);
  assert.deepEqual(out[0].tags, ["a", "b"]);
});

test("baseDomain and authority", () => {
  assert.equal(baseDomain("https://docs.flutter.dev/x"), "flutter.dev");
  assert.equal(baseDomain("https://news.bbc.co.uk/x"), "bbc.co.uk");
  assert.ok(authority("https://en.wikipedia.org/wiki/X") > authority("https://randomblog.example/x"));
  assert.ok(authority("https://www.pinterest.com/pin/1") < authority("https://randomblog.example/x"));
  assert.ok(authority("https://cs.stanford.edu/x") >= 0.9);
});

test("splitPassages drops boilerplate and glues headings", () => {
  const text = [
    "# Reciprocal rank fusion",
    "Reciprocal rank fusion combines several ranked lists by summing 1 / (k + rank) for each document across the lists, which needs no score calibration.",
    "[Home](/) | [About](/about) | [Contact](/contact) | [Blog](/blog)",
    "We use cookies.",
  ].join("\n\n");
  const ps = splitPassages(text);
  assert.equal(ps.length, 1);
  assert.match(ps[0], /^Reciprocal rank fusion: Reciprocal rank fusion combines/);
});

test("BM25 ranks the passage that answers the query first", () => {
  const ps = [
    "The company was founded in 2009 and has offices in three countries across Europe and Asia.",
    "Reciprocal rank fusion scores each document as the sum of 1 over k plus its rank in every list, with k usually set to 60.",
    "Our cookie settings let you control which analytics partners may store data in your browser today.",
  ];
  const ranked = rankPassages(ps, terms("how does reciprocal rank fusion score documents"));
  const best = [...ranked].sort((a, b) => b.score - a.score)[0];
  assert.equal(best.index, 1);
  assert.equal(ranked[2].score, 0);
});

test("selectPassages keeps relevant passages in reading order within budget", () => {
  const filler = (i: number) => `Paragraph ${i} talks about unrelated gardening topics such as tomatoes, soil acidity and watering schedules for summer.`;
  const paras = Array.from({ length: 12 }, (_, i) => filler(i));
  paras[3] = "Flutter 3.41 was released with Impeller improvements and a new widget previewer, according to the release notes published this week.";
  paras[9] = "The Flutter release also raises the minimum Dart version to 3.9 and removes the deprecated web renderer from the stable channel.";
  const out = selectPassages(paras.join("\n\n"), "latest flutter release", { maxChars: 400, maxPassages: 3 });
  assert.ok(out.length <= 400);
  assert.ok(out.indexOf("Flutter 3.41") >= 0);
  assert.ok(out.indexOf("Flutter 3.41") < out.indexOf("Dart version") || out.indexOf("Dart version") < 0);
  assert.ok(!out.includes("Paragraph 0"));
});

test("selectPassages falls back to the page head when nothing matches", () => {
  const text = "First paragraph of the page which is long enough to be kept as a passage on its own.\n\nSecond paragraph that is also long enough to be a proper passage of text.";
  assert.match(selectPassages(text, "zzzz qqqq"), /^First paragraph/);
});

test("circuit breaker opens after repeated failures, probes after the cooldown, and closes on success", () => {
  let t = 1_000;
  const b = new CircuitBreaker({ threshold: 3, cooldownMs: 1000, maxCooldownMs: 8000, now: () => t });
  assert.ok(b.allow("p"));
  b.failure("p");
  b.failure("p");
  assert.equal(b.state("p"), "closed");
  b.failure("p");
  assert.equal(b.state("p"), "open");
  assert.equal(b.allow("p"), false);
  t += 1001;
  assert.equal(b.state("p"), "half-open");
  assert.equal(b.allow("p"), true, "one probe is let through");
  assert.equal(b.allow("p"), false, "but only one at a time");
  b.failure("p"); // probe failed: re-open with a doubled cooldown
  assert.equal(b.state("p"), "open");
  t += 1500;
  assert.equal(b.state("p"), "open");
  t += 600;
  assert.ok(b.allow("p"));
  b.success("p");
  assert.equal(b.state("p"), "closed");
  assert.ok(b.allow("p"));
});

test("circuit breaker: hard failures open at once and Retry-After extends the cooldown", () => {
  let t = 0;
  const b = new CircuitBreaker({ threshold: 3, cooldownMs: 1000, maxCooldownMs: 600_000, now: () => t });
  b.failure("x", { hard: true });
  assert.equal(b.state("x"), "open");
  t += 4000;
  assert.equal(b.state("x"), "open", "hard cooldown is longer than the base");
  t += 1500;
  assert.equal(b.state("x"), "half-open");
  b.success("x");
  b.failure("y", { retryAfterMs: 30_000 });
  b.failure("y", { retryAfterMs: 30_000 });
  b.failure("y", { retryAfterMs: 30_000 });
  t += 20_000;
  assert.equal(b.state("y"), "open");
  assert.equal(b.state("never-seen"), "closed");
});

test("TtlLru expires entries and evicts the least recently used", () => {
  let t = 0;
  const c = new TtlLru<number>(2, () => t);
  c.set("a", 1, 100);
  c.set("b", 2, 100);
  assert.equal(c.get("a"), 1); // a is now most recent
  c.set("c", 3, 100);
  assert.equal(c.get("b"), undefined);
  assert.equal(c.get("a"), 1);
  t += 101;
  assert.equal(c.get("a"), undefined);
});

test("query planning heuristics", () => {
  assert.deepEqual(heuristicQueries("Hey, can you tell me what is RRF in search?").slice(0, 1), ["what is RRF in search"]);
  const fresh = heuristicQueries("latest flutter release", {}, new Date("2026-10-01"));
  assert.deepEqual(fresh, ["latest flutter release", "latest flutter release 2026"]);
  const follow = heuristicQueries("and what about its price?", { previousUser: "Tell me about the Pixel 10 phone" });
  assert.match(follow[0], /Pixel 10 phone.*price/);
  assert.deepEqual(dedupeQueries(["A  b", "a b", "c"]), ["A b", "c"]);
  assert.deepEqual(parsePlan('noise {"queries":["x y","z"],"fresh":"recent"} tail'), { queries: ["x y", "z"], fresh: "recent" });
  assert.equal(parsePlan("no json"), null);
  assert.ok(detectIntents("find a flutter library for charts").includes("repo"));
  assert.ok(detectIntents("paper on reciprocal rank fusion").includes("academic"));
});

test("mergeCandidates dedupes across providers, drops off-topic API hits and ranks multi-source authority higher", () => {
  const c = (source: string, url: string, title: string, rank: number, extra: object = {}) => ({ source, url, title, snippet: title, rank, ...extra });
  const merged = mergeCandidates(
    [
      [c("ollama", "https://blog.example.com/rrf", "Reciprocal rank fusion explained", 0), c("ollama", "https://en.wikipedia.org/wiki/Reciprocal_rank_fusion?utm_source=x", "Reciprocal rank fusion", 1)],
      [c("wikipedia", "https://en.wikipedia.org/wiki/Reciprocal_rank_fusion", "Reciprocal rank fusion - Wikipedia", 0), c("wikipedia", "https://en.wikipedia.org/wiki/Matt_Lucas", "Matt Lucas - Wikipedia", 1)],
    ],
    "evergreen",
    "reciprocal rank fusion",
  );
  assert.equal(merged.length, 2, "Matt Lucas is dropped, the two Wikipedia URLs merge");
  assert.equal(merged[0].url.includes("wikipedia"), true);
  assert.equal(merged[0].sources.size, 2);
});

test("diversify limits hits per domain", () => {
  const items = [
    { url: "https://a.com/1", score: 1 },
    { url: "https://a.com/2", score: 0.9 },
    { url: "https://a.com/3", score: 0.8 },
    { url: "https://b.com/1", score: 0.5 },
  ];
  const out = diversify(items, 4, 2);
  assert.deepEqual(out.map((i) => i.url), ["https://a.com/1", "https://a.com/2", "https://b.com/1"]);
});
