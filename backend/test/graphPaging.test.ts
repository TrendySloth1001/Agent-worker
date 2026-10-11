import { test } from "node:test";
import assert from "node:assert/strict";

// A fake GitHub: the token must exist before the client module loads.
process.env.GITHUB_TOKEN ??= "test-token";

type C = { oid: string; parents: string[]; date: string };
const day = (i: number) => new Date(Date.UTC(2026, 0, 1) + i * 3_600_000).toISOString();
/** Fixed-width ids ("a" + 3 digits) so a1 and a10 never collide. */
const oid = (s: string) => `${s[0]}${s.slice(1).padStart(3, "0")}`.padEnd(40, "0");

// main: m1..m30 (linear). feat: f1..f12 branching off m20, newer than m30.
const commits = new Map<string, C>();
for (let i = 1; i <= 30; i++) commits.set(oid(`a${i}`), { oid: oid(`a${i}`), parents: i > 1 ? [oid(`a${i - 1}`)] : [], date: day(i) });
for (let i = 1; i <= 12; i++) commits.set(oid(`b${i}`), { oid: oid(`b${i}`), parents: [i > 1 ? oid(`b${i - 1}`) : oid("a20")], date: day(30 + i) });
const MAIN = oid("a30");
const FEAT = oid("b12");

/** Ancestors of [head], newest first (what GitHub's history returns). */
function history(head: string): C[] {
  const seen = new Set<string>();
  const out: C[] = [];
  const stack = [head];
  while (stack.length) {
    const c = commits.get(stack.pop()!);
    if (!c || seen.has(c.oid)) continue;
    seen.add(c.oid);
    out.push(c);
    stack.push(...c.parents);
  }
  return out.sort((a, b) => b.date.localeCompare(a.date));
}

const node = (c: C) => ({
  oid: c.oid,
  messageHeadline: `commit ${c.oid.slice(0, 3)}`,
  committedDate: c.date,
  parents: { nodes: c.parents.map((p) => ({ oid: p })) },
  author: { name: "dev", user: null },
});

let calls = 0;
globalThis.fetch = (async (_url: string, init: { body: string }) => {
  calls++;
  const { query, variables: v } = JSON.parse(init.body) as { query: string; variables: Record<string, any> };
  const json = (data: unknown) => new Response(JSON.stringify({ data }), { status: 200, headers: { "content-type": "application/json" } });
  if (query.includes("nameWithOwner")) return json({ repository: { nameWithOwner: "o/r", defaultBranchRef: { name: "main", target: { oid: MAIN } } } });
  if (query.includes("compare(")) {
    return json({ repository: { b0: { name: "feat", target: { oid: FEAT } }, defaultBranchRef: { c0: { aheadBy: 12 } } } });
  }
  const repository: Record<string, unknown> = {};
  for (let i = 0; v[`o${i}`]; i++) {
    const all = history(v[`o${i}`]);
    const start = v[`a${i}`] ? Number(String(v[`a${i}`]).split(" ")[1]) + 1 : 0;
    const part = all.slice(start, start + v[`n${i}`]);
    repository[`s${i}`] = {
      history: {
        totalCount: all.length,
        pageInfo: { hasNextPage: start + part.length < all.length },
        edges: part.map((c, j) => ({ cursor: `${v[`o${i}`]} ${start + j}`, node: node(c) })),
      },
    };
  }
  return json({ repository });
}) as unknown as typeof fetch;

const { graph, mergeStep, decodeCursor } = await import("../src/github/graph.js");

test("graph pages are successive, non-overlapping and complete", async () => {
  const seen: string[] = [];
  let after: string | undefined;
  let pages = 0;
  let total: number | null = null;
  do {
    const g = await graph("o", "r", { branches: "feat", limit: 10, after });
    pages++;
    total = g.totalCount;
    for (const c of g.commits) {
      assert.ok(!seen.includes(c.sha), `duplicate ${c.sha} on page ${pages}`);
      seen.push(c.sha);
    }
    // Within everything loaded so far, children always come before parents.
    const at = new Map(seen.map((s, i) => [s, i]));
    for (const s of seen) for (const p of commits.get(s)!.parents) if (at.has(p)) assert.ok(at.get(p)! > at.get(s)!, `${p} above ${s}`);
    after = g.nextCursor ?? undefined;
    assert.equal(g.truncated, !!g.nextCursor);
  } while (after && pages < 20);
  assert.equal(after, undefined, "the last page has no cursor");
  assert.equal(seen.length, 42);
  assert.equal(total, 30 + 12);
  assert.ok(pages >= 4);
});

test("cursor is bound to the repository", () => {
  const c = Buffer.from(JSON.stringify({ v: 1, s: "graphql", repo: "o/r", def: "main", t: 1, b: [{ n: "main", o: MAIN, d: 1 }] })).toString("base64url");
  assert.ok(decodeCursor(c, "O", "R"));
  assert.throws(() => decodeCursor(c, "x", "y"));
  assert.throws(() => decodeCursor("garbage", "o", "r"));
});

test("mergeStep holds back commits older than another stream's horizon", () => {
  const mk = (sha: string, h: number) => ({ c: { sha, parents: [], subject: "", author: "", authorAvatar: null, date: day(h), refs: [] }, pos: `${sha} 0` });
  const step = mergeStep(
    [
      { n: "main", o: MAIN, d: 1 },
      { n: "feat", o: FEAT, r: 5 },
    ],
    [
      { items: [mk("m3", 10), mk("m2", 5), mk("m1", 1)], more: true },
      { items: [mk("f2", 9), mk("f1", 7)], more: true },
    ],
  );
  // Horizon = feat's last fetched date (7): main's m2 and m1 wait for the next page.
  assert.deepEqual(step.emitted.map((c) => c.sha).sort(), ["f1", "f2", "m3"]);
  assert.equal(step.streams[0].a, "m3 0");
  assert.equal(step.streams[1].r, 3);
  assert.ok(calls >= 0);
});
