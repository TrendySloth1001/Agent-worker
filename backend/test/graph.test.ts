import { test } from "node:test";
import assert from "node:assert/strict";
import { buildGraph, clampLimit, orderCommits, parseBranches, type GraphCommit } from "../src/github/graph.js";
import { AppError } from "../src/util/errors.js";

const c = (sha: string, parents: string[], date: string): GraphCommit => ({ sha, parents, subject: sha, author: "a", authorAvatar: null, date, refs: [] });

test("children stay above parents even when the parent's date is newer", () => {
  // b's committer date is older than its parent a (clock skew / rebase).
  const list = [c("a", ["root"], "2024-01-03T00:00:00Z"), c("b", ["a"], "2024-01-01T00:00:00Z"), c("root", [], "2024-01-02T00:00:00Z")];
  assert.deepEqual(orderCommits(list).map((x) => x.sha), ["b", "a", "root"]);
});

test("date order between independent lines", () => {
  const list = [
    c("m2", ["m1", "f2"], "2024-01-05T00:00:00Z"),
    c("f2", ["f1"], "2024-01-04T00:00:00Z"),
    c("m1", ["base"], "2024-01-03T00:00:00Z"),
    c("f1", ["base"], "2024-01-02T00:00:00Z"),
    c("base", [], "2024-01-01T00:00:00Z"),
  ];
  assert.deepEqual(orderCommits(list.reverse()).map((x) => x.sha), ["m2", "f2", "m1", "f1", "base"]);
});

test("buildGraph dedupes, sets refs, caps and marks truncated", () => {
  const main = [c("m2", ["m1"], "2024-01-03T00:00:00Z"), c("m1", ["m0"], "2024-01-01T00:00:00Z")];
  const feat = [c("f1", ["m1"], "2024-01-02T00:00:00Z"), c("m1", ["m0"], "2024-01-01T00:00:00Z")];
  const branches = [
    { name: "main", sha: "m2", isDefault: true },
    { name: "feat", sha: "f1", isDefault: false },
  ];
  const g = buildGraph("o/r", "main", branches, [main, feat], 2, false, "graphql");
  assert.deepEqual(g.commits.map((x) => x.sha), ["m2", "f1"]);
  assert.deepEqual(g.commits[1].refs, ["feat"]);
  assert.equal(g.truncated, true);
});

test("query parsing", () => {
  assert.deepEqual(parseBranches("main, dev ,main"), ["main", "dev"]);
  assert.deepEqual(parseBranches(undefined), []);
  assert.throws(() => parseBranches("a..b"), AppError);
  assert.equal(clampLimit("999"), 300);
  assert.equal(clampLimit(undefined), 150);
});
