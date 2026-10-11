import { test } from "node:test";
import assert from "node:assert/strict";

process.env.GITHUB_TOKEN ??= "test-token";

// Fake GitHub GraphQL: 250 commits on HEAD, 230 branches (cursors are base64 offsets, like GitHub's).
const COMMITS = Array.from({ length: 250 }, (_, i) => ({
  oid: `c${String(i).padStart(3, "0")}`.padEnd(40, "0"),
  messageHeadline: `commit ${i}`,
  messageBody: "",
  authoredDate: new Date(Date.UTC(2026, 0, 1) - i * 60_000).toISOString(),
  url: `https://github.com/o/r/commit/${i}`,
  additions: i,
  deletions: 1,
  parents: { totalCount: 1 },
  author: { name: "dev", email: "d@x", user: { login: "dev", avatarUrl: "", url: "" } },
}));
const BRANCHES = Array.from({ length: 230 }, (_, i) => ({
  name: i === 0 ? "main" : `feature/b${i}`,
  target: { oid: "f".repeat(40), committedDate: new Date(Date.UTC(2026, 0, 1) + i * 60_000).toISOString() },
}));

globalThis.fetch = (async (_url: string, init: { body: string }) => {
  const { query, variables: v } = JSON.parse(init.body) as { query: string; variables: Record<string, any> };
  const json = (data: unknown) => new Response(JSON.stringify({ data }), { status: 200 });
  if (query.includes("refs(")) {
    const off = v.after ? Number(Buffer.from(v.after, "base64").toString()) : 0;
    const nodes = BRANCHES.slice(off, off + 100);
    return json({
      repository: {
        defaultBranchRef: { name: "main" },
        refs: {
          totalCount: BRANCHES.length,
          pageInfo: { hasNextPage: off + 100 < BRANCHES.length, endCursor: Buffer.from(String(off + nodes.length)).toString("base64") },
          nodes,
        },
      },
    });
  }
  const start = v.after ? Number(v.after) : 0;
  const nodes = COMMITS.slice(start, start + v.n);
  return json({
    repository: {
      object: {
        history: {
          totalCount: COMMITS.length,
          pageInfo: { hasNextPage: start + nodes.length < COMMITS.length, endCursor: String(start + nodes.length) },
          nodes,
        },
      },
    },
  });
}) as unknown as typeof fetch;

const svc = await import("../src/github/service.js");
const { githubIntent } = await import("../src/github/grounding.js");

test("commit pages follow the cursor to the end with a total", async () => {
  const shas: string[] = [];
  let after: string | undefined;
  let total: number | null = null;
  for (let i = 0; i < 10; i++) {
    const p = await svc.commitsPage("o", "r", { perPage: 100, after });
    total = p.totalCount;
    shas.push(...p.items.map((c) => c.sha));
    if (!p.nextCursor) break;
    assert.ok(p.nextCursor.startsWith("g:"));
    after = p.nextCursor;
  }
  assert.equal(total, 250);
  assert.equal(shas.length, 250);
  assert.equal(new Set(shas).size, 250);
});

test("branches: all pages, default first, newest next, fuzzy filter, offset paging", async () => {
  const b = await svc.branches("o", "r", { limit: 50 });
  assert.equal(b.totalCount, 230);
  assert.equal(b.items[0].name, "main");
  assert.equal(b.items[1].name, "feature/b229");
  assert.equal(b.nextCursor, "50");
  const next = await svc.branches("o", "r", { limit: 50, after: b.nextCursor! });
  assert.equal(next.items[0].name, "feature/b180");
  const f = await svc.branches("o", "r", { q: "b42" });
  assert.equal(f.items[0].name, "feature/b42");
});

test("intent: loosely named repositories", () => {
  assert.equal(githubIntent("show commits of my keepit repo")?.myRepo, "keepit");
  assert.equal(githubIntent("my report card generator project")?.myRepo, "report card generator");
  assert.equal(githubIntent("my repo called keepit")?.myRepo, "keepit");
  assert.equal(githubIntent("what changed in the reprot card repo")?.looseRepo, "reprot card");
  assert.equal(githubIntent("show my private repos")?.myRepo, null);
  assert.equal(githubIntent("show my private repos")?.mine?.visibility, "private");
});
