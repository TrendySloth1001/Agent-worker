// Deterministic cost simulation for web search: mocked engines and a mocked page reader count
// upstream calls per turn for representative questions. The assertions lock the budgets in.
import assert from "node:assert/strict";
import { afterEach, before, test } from "node:test";
import { breaker, clearProviderCache, PROVIDERS, ProviderError, type Provider } from "../src/web/providers.js";
import { clearResearchCache, researchWeb, resetPageHealth, setPageReader, setWebEmbedder } from "../src/web/pipeline.js";
import type { Candidate } from "../src/web/types.js";

const nonce = Math.random().toString(36).slice(2, 8);
const DOMAINS = ["alpha.example", "bravo.example", "charlie.example", "delta.example", "echo.example", "foxtrot.example"];

type Counters = { web: Record<string, number>; topical: Record<string, number>; fetches: number; fetchedUrls: string[] };
let c: Counters;
const reset = () => (c = { web: {}, topical: {}, fetches: 0, fetchedUrls: [] });
reset();

/** A short-snippet result list, so pages have to be read to answer. */
const hits = (src: string, query: string): Candidate[] =>
  DOMAINS.map((d, i) => ({ title: `${query} ${i}`, url: `https://${d}/${src}/${encodeURIComponent(query).slice(0, 40)}`, snippet: `${query} short snippet ${i}`, source: src, rank: i }));

const engine = (name: string, role: Provider["role"], intents: Provider["intents"], o: { fail?: ProviderError; empty?: boolean } = {}): Provider => ({
  name,
  role,
  intents,
  timeoutMs: 1_000,
  enabled: () => true,
  async search(query) {
    const bucket = role === "web" ? c.web : c.topical;
    bucket[name] = (bucket[name] ?? 0) + 1;
    if (o.fail) throw o.fail;
    return o.empty ? [] : hits(name, query);
  },
});

const original = [...PROVIDERS];
let restorePages = () => {};
let restoreEmbedder = () => {};

function install(providers: Provider[], failHosts: string[] = []): void {
  PROVIDERS.splice(0, PROVIDERS.length, ...providers);
  clearProviderCache();
  clearResearchCache();
  resetPageHealth();
  reset();
  restorePages();
  restorePages = setPageReader(async (url) => {
    c.fetches++;
    c.fetchedUrls.push(url);
    if (failHosts.some((h) => url.includes(h))) throw new Error("HTTP 503");
    return { body: `<html><head><title>Page</title></head><body><article><p>${"Detailed article text about the subject with plenty of facts, names and numbers. ".repeat(30)}</p></article></body></html>`, contentType: "text/html", url, status: 200 };
  });
}

before(() => {
  restoreEmbedder = setWebEmbedder(null);
});
afterEach(() => {
  PROVIDERS.splice(0, PROVIDERS.length, ...original);
  restorePages();
});

const sum = (r: Record<string, number>) => Object.values(r).reduce((a, b) => a + b, 0);
const rows: string[] = [];
const note = (scenario: string, turns: number) => rows.push(`${scenario.padEnd(34)} turns=${turns}  web/turn=${(sum(c.web) / turns).toFixed(2)}  topical/turn=${(sum(c.topical) / turns).toFixed(2)}  search/turn=${((sum(c.web) + sum(c.topical)) / turns).toFixed(2)}  fetch/turn=${(c.fetches / turns).toFixed(2)}`);
const standardChain = (n = "") => [engine(`sim-ddg${n}`, "web", "any"), engine(`sim-lite${n}`, "web", "any"), engine(`sim-wiki${n}`, "secondary", ["encyclopedic", "academic"]), engine(`sim-news${n}`, "secondary", ["news"]), engine(`sim-hn${n}`, "secondary", ["discussion", "repo"]), engine(`sim-so${n}`, "secondary", ["code"]), engine(`sim-gh${n}`, "secondary", ["repo"])];

test("factual question: one engine call, at most one topical source, at most 3 page reads", async () => {
  install(standardChain("a"));
  const out = await researchWeb({ question: `Who directed the film Oppenheimer ${nonce}a?` });
  assert.ok(out.length > 0);
  note("factual", 1);
  assert.equal(sum(c.web), 1, "the first engine answered: the second is not asked");
  assert.ok(sum(c.topical) <= 1);
  assert.ok(c.fetches <= 3, `fetches ${c.fetches}`);
});

test("news question: one engine, the news source, bounded fetches", async () => {
  install(standardChain("b"));
  const out = await researchWeb({ question: `latest news about the Starship launch today ${nonce}b` });
  assert.ok(out.length > 0);
  note("news", 1);
  assert.equal(sum(c.web), 1);
  assert.ok(sum(c.topical) <= 1);
  assert.ok(c.fetches <= 3);
});

test("discussion/comparison question: at most 2 queries, one topical source", async () => {
  install(standardChain("c"));
  await researchWeb({ question: `React vs Vue which is better reviews and opinions ${nonce}c` });
  note("comparison + discussion", 1);
  assert.ok(sum(c.web) <= 2, `web calls ${sum(c.web)}`);
  assert.ok(sum(c.topical) <= 1, `topical calls ${sum(c.topical)}`);
  assert.ok(c.fetches <= 3);
});

test("repeated question and same-topic follow-up in the chat reuse the previous sources", async () => {
  install(standardChain("d"));
  const q = `Who directed the film Interstellar ${nonce}d`;
  await researchWeb({ question: q, conversationId: "conv-1" });
  const first = { search: sum(c.web) + sum(c.topical), fetch: c.fetches };
  await researchWeb({ question: q.toUpperCase() + "?", conversationId: "conv-1" }); // repeated
  await researchWeb({ question: "who directed it", context: { previousUser: q, standalone: `directed film Interstellar ${nonce}d released` }, conversationId: "conv-1" }); // follow-up, same topic
  note("factual + repeat + follow-up", 3);
  assert.equal(sum(c.web) + sum(c.topical), first.search, "no further engine call");
  assert.equal(c.fetches, first.fetch, "no further page read");
});

test("a rate-limited engine is skipped for a while: later turns go straight to the next one", async () => {
  const limited = engine("sim-limited", "web", "any", { fail: new ProviderError("HTTP 429", 429) });
  install([limited, engine("sim-ok", "web", "any")]);
  for (let i = 0; i < 4; i++) await researchWeb({ question: `Who wrote the novel Dune part ${i} ${nonce}e` });
  note("429 engine, 4 turns", 4);
  assert.equal(c.web["sim-limited"], 1, "asked once, then skipped");
  assert.equal(c.web["sim-ok"], 4);
  assert.equal(breaker.state("sim-limited"), "open");
});

test("an engine that fails or comes back empty falls through to the next one, once", async () => {
  install([engine("sim-dead", "web", "any", { fail: new ProviderError("HTTP 500", 500) }), engine("sim-live", "web", "any")]);
  const out = await researchWeb({ question: `Who founded the company Anthropic ${nonce}f` });
  assert.ok(out.length > 0);
  assert.equal(c.web["sim-dead"], 1);
  assert.equal(c.web["sim-live"], 1);
});

test("pages from a host that keeps failing are skipped on later turns", async () => {
  install([engine("sim-g", "web", "any")], ["alpha.example", "bravo.example"]);
  await researchWeb({ question: `Who invented the telephone first ${nonce}g1` });
  await researchWeb({ question: `Who invented the lightbulb first ${nonce}g2` });
  const before = c.fetchedUrls.length;
  await researchWeb({ question: `Who invented the airplane first ${nonce}g3` });
  note("failing hosts, 3 turns", 3);
  const turn3 = c.fetchedUrls.slice(before);
  assert.ok(turn3.length > 0 && turn3.length <= 3);
  assert.ok(turn3.every((u) => !/alpha|bravo/.test(u)), `turn 3 re-tried failing hosts: ${turn3.join(" ")}`);
  assert.ok(c.fetches / 3 <= 3);
});

test("reports the numbers", () => {
  console.log(`\n--- web cost simulation ---\n${rows.join("\n")}\n`);
  restoreEmbedder();
});
