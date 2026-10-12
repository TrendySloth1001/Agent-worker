import assert from "node:assert/strict";
import { test } from "node:test";
import {
  TOOL_BUDGET_TOKENS,
  buildTurnContextFromText,
  extractTopics,
  imageQuery,
  renderContext,
  topicTerms,
  trimTurns,
  type TurnMessage,
} from "../src/context/turnContext.js";
import { heuristicStandalone, needsRewrite } from "../src/retrieval/rewrite.js";
import { githubIntent, resolveRepoReference } from "../src/github/grounding.js";
import { heuristicQueries } from "../src/web/plan.js";

const chat: TurnMessage[] = [
  { role: "user", content: "Tell me about the facebook/react repo on GitHub" },
  { role: "assistant", content: "React is a UI library by Meta. The repo github.com/facebook/react has many contributors and uses Flow." },
  { role: "user", content: "what about the second one?" },
];

test("trimTurns keeps the newest turns within the budget, oldest first", () => {
  const msgs = Array.from({ length: 20 }, (_, i) => ({ role: i % 2 ? "assistant" : "user", content: `message number ${i} ` + "word ".repeat(50) }));
  const out = trimTurns(msgs, 300, 400, 8);
  assert.ok(out.length >= 1 && out.length < 8, `kept ${out.length}`);
  assert.ok(out.reduce((n, m) => n + m.content.length, 0) <= 300 * 4);
  assert.match(out[out.length - 1].content, /message number 19/);
  assert.deepEqual(out.map((m) => m.content.slice(0, 17)), [...out.map((m) => m.content.slice(0, 17))].sort());
});

test("trimTurns always keeps the newest turn, cut to fit, and caps each message", () => {
  const out = trimTurns([{ role: "user", content: "x ".repeat(5000) }], 50, 600, 8);
  assert.equal(out.length, 1);
  assert.ok(out[0].content.length <= 200);
  const capped = trimTurns([{ role: "user", content: "y".repeat(5000) }], 5000, 600, 8);
  assert.ok(capped[0].content.length <= 600);
  assert.deepEqual(trimTurns([], 100), []);
});

test("topics: repos, files, docs and named things from earlier turns, newest first", () => {
  const msgs: TurnMessage[] = [
    ...chat.slice(0, 2),
    { role: "user", content: "Also look at src/index.ts and notes.md. See doc:123e4567-e89b-12d3-a456-426614174000 for Prisma details", attachments: ["f1"] },
  ];
  const t = extractTopics(msgs, new Map([["f1", { id: "f1", name: "design.pdf", kind: "document" }]]));
  assert.equal(t.repos[0], "facebook/react");
  assert.ok(t.files.includes("design.pdf") && t.files.includes("notes.md"));
  assert.deepEqual(t.docs, ["123e4567-e89b-12d3-a456-426614174000"]);
  assert.ok(t.entities.some((e) => /prisma/i.test(e)));
});

test("buildTurnContext: accumulates entities and intents, trims turns, resolves the standalone question once", async () => {
  let calls = 0;
  const ctx = await buildTurnContextFromText(
    chat,
    { summary: "  The user is exploring UI libraries.  " },
    { rewrite: async (q) => (calls++, { standalone: `What about the second UI library after React? (${q})`, queries: ["second UI library"], via: "model" as const }) },
  );
  assert.equal(calls, 1);
  assert.equal(ctx.rewrittenBy, "model");
  assert.match(ctx.standalone, /second UI library/);
  assert.equal(ctx.summary, "The user is exploring UI libraries.");
  assert.equal(ctx.topics.repos[0], "facebook/react");
  assert.ok(ctx.entities.some((e) => e.type === "repo" || /react/i.test(e.value)), "entities from the earlier turn are kept");
  assert.ok(ctx.recentIntents.length >= 1);
  // The latest user message is not part of the earlier turns.
  assert.equal(ctx.turns.length, 2);
  assert.equal(ctx.lastUser, "what about the second one?");
});

test("buildTurnContext: no rewrite for a standalone question or a first message", async () => {
  let calls = 0;
  const deps = { rewrite: async () => (calls++, { standalone: "x", queries: [], via: "model" as const }) };
  const first = await buildTurnContextFromText([{ role: "user", content: "what about the second one?" }], {}, deps);
  assert.equal(first.rewrittenBy, "none");
  const standalone = await buildTurnContextFromText(
    [...chat.slice(0, 2), { role: "user", content: "How does the Linux scheduler decide which process runs next when many are ready to run?" }],
    {},
    deps,
  );
  assert.equal(standalone.rewrittenBy, "none");
  assert.equal(calls, 0);
  assert.equal(standalone.standalone.startsWith("How does the Linux"), true);
});

test("buildTurnContext: a failing or timed-out rewrite falls back to the heuristic", async () => {
  const ctx = await buildTurnContextFromText(chat, {}, { rewrite: async () => { throw new Error("timeout"); } });
  assert.equal(ctx.rewrittenBy, "heuristic");
  assert.match(ctx.standalone, /facebook\/react repo/);
  assert.match(ctx.standalone, /what about the second one/);
});

test("past reference is detected on the latest message", async () => {
  const ctx = await buildTurnContextFromText([{ role: "user", content: "Did we talk about Redis before?" }], {}, { rewrite: async () => ({ standalone: "", queries: [], via: "none" as const }) });
  assert.equal(ctx.pastRef.explicit, true);
  assert.match(ctx.pastRef.topic, /redis/i);
});

test("coreference fallback: referential messages borrow the previous question, standalone ones are untouched", () => {
  const history = [
    { role: "user", content: "How do I deploy a Next.js app to Vercel?" },
    { role: "assistant", content: "Push to GitHub, import the project, done." },
  ];
  assert.equal(needsRewrite("and the cost?", history), true);
  assert.equal(heuristicStandalone("and the cost?", history), "How do I deploy a Next.js app to Vercel - and the cost?");
  const long = "Compare the memory model of Rust and Go for concurrent programs in detail please";
  assert.equal(heuristicStandalone(long, history), long);
  // Without a previous user message the chat topics are used.
  assert.equal(heuristicStandalone("what about it?", [{ role: "assistant", content: "Hello" }], ["facebook/react"]), "facebook/react - what about it?");
  // Nothing to borrow from: unchanged.
  assert.equal(heuristicStandalone("what about it?", [{ role: "assistant", content: "Hello" }]), "what about it?");
});

test("renderContext respects each tool's token budget and prioritises the summary", async () => {
  const long = Array.from({ length: 12 }, (_, i) => ({ role: i % 2 ? ("assistant" as const) : ("user" as const), content: `turn ${i} ` + "details ".repeat(120) }));
  const ctx = await buildTurnContextFromText([...long, { role: "user", content: "and then?" }], { summary: "Summary text. ".repeat(300) }, { rewrite: async () => ({ standalone: "and then?", queries: [], via: "none" as const }) });
  for (const tool of ["images", "github", "web", "followups", "table"] as const) {
    const text = renderContext(ctx, tool);
    assert.ok(text.length <= TOOL_BUDGET_TOKENS[tool] * 4 + 200, `${tool}: ${text.length}`);
  }
  assert.match(renderContext(ctx, "followups"), /^Earlier in this chat: Summary text/);
  assert.ok(renderContext(ctx, "table").length > renderContext(ctx, "web").length);
  assert.equal(renderContext({ summary: null, topics: { repos: [], files: [], docs: [], entities: [] }, turns: [] }, "web"), "");
});

test("tools: topic terms for web, image topic for bare follow-ups, repo resolution for GitHub", async () => {
  const ctx = await buildTurnContextFromText(chat, {}, { rewrite: async () => ({ standalone: "", queries: [], via: "none" as const }) });
  assert.equal(topicTerms(ctx, "web")[0], "facebook/react");
  assert.match(imageQuery("show me pictures of it", ctx), /react|facebook/i);
  assert.equal(imageQuery("show me the TCP three way handshake diagram", ctx), "show me the TCP three way handshake diagram");
  assert.equal(imageQuery("pictures of it", null), "pictures of it");

  assert.equal(githubIntent("show me its latest commits"), null);
  const resolved = resolveRepoReference("show me its latest commits", ["facebook/react"]);
  assert.deepEqual(githubIntent(resolved)?.repos, [{ owner: "facebook", repo: "react" }]);
  assert.equal(githubIntent(resolved)?.commits, true);
  assert.equal(resolveRepoReference("any open issues on that repo?", ["vercel/next.js"]), "any open issues on that repo? vercel/next.js");
  // Unchanged: names a repo, is personal, is not about GitHub, or nothing to resolve.
  assert.equal(resolveRepoReference("commits of denoland/deno", ["facebook/react"]), "commits of denoland/deno");
  assert.equal(resolveRepoReference("list my repos", ["facebook/react"]), "list my repos");
  assert.equal(resolveRepoReference("what is the capital of France", ["facebook/react"]), "what is the capital of France");
  assert.equal(resolveRepoReference("show me its latest commits", []), "show me its latest commits");
});

test("web planning: topics and the standalone question steer follow-ups; nothing changes without context", () => {
  assert.deepEqual(heuristicQueries("what about pricing?"), heuristicQueries("what about pricing?", {}));
  const withTopics = heuristicQueries("what about pricing?", { topics: ["Vercel", "Next.js"] });
  assert.match(withTopics[0], /^Vercel Next\.js what about pricing/);
  const withStandalone = heuristicQueries("what about pricing?", { standalone: "What is the pricing of Vercel for Next.js apps?", previousUser: "deploy to vercel" });
  assert.match(withStandalone[0], /pricing of Vercel/);
  const prevOnly = heuristicQueries("what about pricing?", { previousUser: "deploy to vercel" });
  assert.match(prevOnly[0], /^deploy to vercel what about pricing/);
});
