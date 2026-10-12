import assert from "node:assert/strict";
import { test } from "node:test";
import { chunkMarkdown, embeddingInput, estTokens } from "../src/ingest/chunk.js";
import { cleanDocMarkdown } from "../src/ingest/connectors/doc.js";
import { structureText } from "../src/ingest/structure.js";
import { cosine, joinOverlap, mmr, parseVector, rrfFuse } from "../src/retrieval/fusion.js";
import { needsRewrite } from "../src/retrieval/rewrite.js";
import { keywordQuery } from "../src/retrieval/search.js";

const para = (word: string, n: number) => Array.from({ length: n }, (_, i) => `${word}${i}`).join(" ") + ".";

test("chunker keeps heading paths and splits on headings", () => {
  const md = `# Guide\n\nIntro text that is long enough to keep around for the test ${para("a", 20)}\n\n## Install\n\n${para("b", 30)}\n\n### Linux\n\n${para("c", 30)}\n\n## Usage\n\n${para("d", 30)}`;
  const chunks = chunkMarkdown(md, "Guide");
  const paths = chunks.map((c) => c.headingPath);
  assert.ok(paths.includes("Guide > Install"));
  assert.ok(paths.includes("Guide > Install > Linux"));
  assert.ok(paths.includes("Guide > Usage"));
  assert.deepEqual(chunks.map((c) => c.ord), chunks.map((_, i) => i));
  assert.ok(chunks.every((c) => c.content.length > 0 && c.hash.length === 64));
});

test("chunker never splits inside a code fence and respects the size cap", () => {
  const code = Array.from({ length: 400 }, (_, i) => `const value${i} = compute(${i});`).join("\n");
  const md = `## Code\n\nBefore.\n\n\`\`\`ts\n${code}\n\`\`\`\n\nAfter the block.`;
  const chunks = chunkMarkdown(md, null);
  for (const c of chunks) {
    assert.ok(estTokens(c.content) <= 900, `chunk too large: ${estTokens(c.content)}`);
    const fences = (c.content.match(/^```/gm) ?? []).length;
    assert.equal(fences % 2, 0, "fence opened and closed within a chunk");
  }
  assert.ok(chunks.length >= 2);
});

test("chunker overlaps consecutive chunks of one section", () => {
  const paragraphs = Array.from({ length: 12 }, (_, i) => para(`p${i}w`, 60)).join("\n\n");
  const chunks = chunkMarkdown(`## Long\n\n${paragraphs}`, "Doc");
  assert.ok(chunks.length >= 2);
  const tail = chunks[0].content.slice(-100).trim().split(/\s+/).slice(-3).join(" ");
  assert.ok(chunks[1].content.includes(tail), "next chunk starts with the previous chunk's tail");
});

test("chunker merges tiny sections and embeds with the heading path", () => {
  const chunks = chunkMarkdown("## A\n\nshort one line of text here that is tiny.\n\n## B\n\n" + para("z", 80), "T");
  assert.ok(chunks.length >= 1);
  assert.equal(embeddingInput({ headingPath: "T > A", content: "x" }), "T > A\nx");
  assert.equal(embeddingInput({ headingPath: null, content: "x" }), "x");
});

test("chunker handles empty and heading-only input", () => {
  assert.deepEqual(chunkMarkdown("", "T"), []);
  assert.deepEqual(chunkMarkdown("# Only a heading", "T"), []);
});

test("rrfFuse ranks documents found by both lists first", () => {
  const fused = rrfFuse([{ ids: ["a", "b", "c", "d"] }, { ids: ["c", "e", "a"] }], 60);
  assert.deepEqual(fused.slice(0, 2).map((f) => f.id), ["a", "c"]);
  assert.equal(fused.length, 5);
  const a = fused.find((f) => f.id === "a")!;
  assert.ok(Math.abs(a.score - (1 / 61 + 1 / 63)) < 1e-12);
  assert.deepEqual(a.lists, [0, 1]);
});

test("rrfFuse honours weights and counts duplicates once", () => {
  const fused = rrfFuse([{ ids: ["x", "y"], weight: 1 }, { ids: ["y", "x"], weight: 0.5 }, { ids: ["y", "y", "y"], weight: 0.1 }]);
  assert.equal(fused[0].id, "y");
  const y = fused.find((f) => f.id === "y")!;
  assert.ok(Math.abs(y.score - (1 / 62 + 0.5 / 61 + 0.1 / 61)) < 1e-12);
  assert.deepEqual(rrfFuse([]), []);
});

test("mmr drops near-duplicates and prefers diversity", () => {
  const v = (...x: number[]) => Float32Array.from(x);
  const picked = mmr(
    [
      { id: 1, relevance: 1.0, vec: v(1, 0, 0) },
      { id: 2, relevance: 0.99, vec: v(0.999, 0.01, 0) }, // near-duplicate of 1
      { id: 3, relevance: 0.8, vec: v(0, 1, 0) },
      { id: 4, relevance: 0.7, vec: v(0.6, 0.6, 0.5) },
    ],
    3,
  );
  assert.equal(picked[0], 1);
  assert.ok(!picked.includes(2));
  assert.ok(picked.includes(3));
  assert.deepEqual(mmr([], 3), []);
  // without vectors it is plain relevance order
  assert.deepEqual(mmr([{ id: "a", relevance: 1, vec: null }, { id: "b", relevance: 2, vec: null }], 2), ["b", "a"]);
});

test("cosine and parseVector", () => {
  assert.ok(Math.abs(cosine([1, 0], [1, 0]) - 1) < 1e-9);
  assert.equal(cosine([1, 0], [0, 1]), 0);
  assert.deepEqual([...parseVector("[0.5,-1,2]")], [0.5, -1, 2]);
});

test("joinOverlap removes the chunker's overlap", () => {
  const tail = "the shared sentence that both chunks contain";
  const a = `First part of the text. ${tail}`;
  const b = `${tail}\n\nSecond part continues here.`;
  assert.equal(joinOverlap(a, b), `First part of the text. ${tail}\n\nSecond part continues here.`);
  assert.equal(joinOverlap("alpha", "beta"), "alpha\n\nbeta");
});

test("chunker overlap round-trips through joinOverlap", () => {
  const paragraphs = Array.from({ length: 10 }, (_, i) => para(`q${i}w`, 70)).join("\n\n");
  const [c0, c1] = chunkMarkdown(`## S\n\n${paragraphs}`, null);
  const joined = joinOverlap(c0.content, c1.content);
  assert.ok(joined.length < c0.content.length + c1.content.length, "overlap removed");
});

test("structureText turns page markers and numbered lines into headings", () => {
  const out = structureText("--- Page 1 ---\n1. Introduction\nSome sentence here.\n2.1 Details\nMore text.\n\n--- Page 2 ---\nTHE SUMMARY\nEnd.");
  assert.match(out, /^## Page 1$/m);
  assert.match(out, /^#{3,} 1\. Introduction$/m);
  assert.match(out, /^#{3,} 2\.1 Details$/m);
  assert.match(out, /^## Page 2$/m);
  assert.match(out, /^### THE SUMMARY$/m);
  const chunks = chunkMarkdown(out, "report.pdf");
  assert.ok(chunks.some((c) => c.headingPath?.includes("Page 1 > 1. Introduction")));
});

test("structureText leaves existing Markdown headings alone", () => {
  const md = "# Title\n\n1. First list item\n2. Second item\n\nTEXT LINE\n";
  assert.equal(structureText(md), md);
});

test("cleanDocMarkdown strips citation tags and placeholders", () => {
  const md = "Redis listens on 6379 [K1][W2]. See also [D3].\n\n{{image:diagram}}\n\n![x](http://a/b.png)\n\n\n\nDone.";
  assert.equal(cleanDocMarkdown(md), "Redis listens on 6379. See also.\n\nDone.");
});

test("keywordQuery keeps identifiers and ORs the terms", () => {
  assert.equal(keywordQuery("How do I use useState in .NET?"), "how or use or usestate or net");
  assert.equal(keywordQuery("a b"), "");
});

test("needsRewrite only fires for context-dependent follow-ups", () => {
  const history = [
    { role: "user", content: "What is pgvector?" },
    { role: "assistant", content: "A Postgres extension for vector similarity." },
  ];
  assert.equal(needsRewrite("how do I install it?", history), true);
  assert.equal(needsRewrite("and the index?", history), true);
  assert.equal(needsRewrite("What retention period do the nightly backups of the production cluster use for point in time recovery?", history), false);
  assert.equal(needsRewrite("how do I install it?", [{ role: "user", content: "hi" }]), false);
  assert.equal(needsRewrite("", history), false);
});
