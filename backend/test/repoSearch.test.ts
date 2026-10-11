import { test } from "node:test";
import assert from "node:assert/strict";
import {
  CONFIDENT,
  damerau,
  publicAttempts,
  rankNames,
  rankRepos,
  repairTypos,
  tokens,
  trigramSim,
  type RankableRepo,
} from "../src/github/repoSearch.js";

const NOW = Date.parse("2026-10-11T00:00:00Z");
const daysAgo = (d: number) => new Date(NOW - d * 86_400_000).toISOString();
const r = (fullName: string, extra: Partial<RankableRepo> = {}): RankableRepo => {
  const [owner, name] = fullName.split("/");
  return { fullName, owner, name, description: "", topics: [], pushedAt: daysAgo(400), stars: 0, ...extra };
};

const REPOS = [
  r("nick/report-card-generator", { description: "Generates school report cards", pushedAt: daysAgo(30) }),
  r("nick/card-games"),
  r("nick/keepit", { pushedAt: daysAgo(100) }),
  r("nick/keepit-web", { pushedAt: daysAgo(1) }),
  r("nick/keep-notes", { pushedAt: daysAgo(1) }),
  r("nick/Agent-worker", { pushedAt: daysAgo(0) }),
  r("eysium/report-card", { pushedAt: daysAgo(200) }),
  r("nick/eysium-site"),
  r("nick/rcg", { description: "Report card generator for teachers" }),
];
const top = (q: string, list = REPOS) => rankRepos(q, list, { now: NOW });

test("tokens split camelCase, kebab, snake, dots and digits", () => {
  assert.deepEqual(tokens("ReportCard_generator-v2.js"), ["report", "card", "generator", "v", "2", "js"]);
  assert.deepEqual(tokens("Agent-worker"), ["agent", "worker"]);
});

test("distance helpers", () => {
  assert.equal(damerau("reprot", "report"), 1);
  assert.equal(damerau("databse", "database"), 1);
  assert.ok(trigramSim("keepit", "keepit") === 1);
  assert.ok(trigramSim("abc", "xyz") === 0);
});

test("typos: 'reprot card' finds report-card-generator", () => {
  const res = top("reprot card");
  assert.ok(res.items[0].repo.fullName.endsWith("report-card") || res.items[0].repo.fullName.endsWith("report-card-generator"));
  assert.ok(res.items[0].score >= CONFIDENT);
  assert.ok(!res.items.slice(0, 2).some((x) => x.repo.name === "card-games"));
});

test("partial 'report' prefers report repos over others", () => {
  const names = top("report").items.slice(0, 2).map((x) => x.repo.name);
  assert.ok(names.every((n) => n.startsWith("report-card")), names.join());
});

test("kebab vs spaced: 'report card generator' is an exact name match", () => {
  const res = top("my report card generator repo");
  assert.equal(res.items[0].repo.fullName, "nick/report-card-generator");
  assert.ok(res.confident);
});

test("owner-prefixed 'eysium report' picks the eysium repo", () => {
  assert.equal(top("eysium report").items[0].repo.fullName, "eysium/report-card");
  assert.equal(top("eysium/report-card").items[0].repo.fullName, "eysium/report-card");
});

test("exact beats fuzzy and prefix, even when they are newer", () => {
  const res = top("keepit");
  assert.equal(res.items[0].repo.fullName, "nick/keepit");
  assert.ok(res.confident);
  assert.equal(top("agent worker").items[0].repo.name, "Agent-worker");
});

test("recency breaks ties", () => {
  const list = [r("a/notes-app", { pushedAt: daysAgo(300) }), r("b/notes-app", { pushedAt: daysAgo(2) })];
  assert.equal(top("notes app", list).items[0].repo.fullName, "b/notes-app");
});

test("description hits find a repo with a cryptic name", () => {
  const list = [r("nick/rcg", { description: "Report card generator for teachers" }), r("nick/card-games")];
  assert.equal(top("the report card generator", list).items[0].repo.fullName, "nick/rcg");
});

test("no confident match for unrelated text", () => {
  const res = top("kubernetes operator");
  assert.equal(res.confident, false);
});

test("ambiguous near-ties are not confident", () => {
  const list = [r("a/report-card", { pushedAt: daysAgo(5) }), r("b/report-card", { pushedAt: daysAgo(6) })];
  assert.equal(top("report card", list).confident, false);
});

test("branch names rank by fuzzy match", () => {
  const out = rankNames("fix login", ["main", "fix/login-redirect", "feature/logging"], (x) => x).map((x) => x.item);
  assert.equal(out[0], "fix/login-redirect");
});

test("public search: typo repair and attempts", () => {
  assert.equal(repairTypos("vectr databse"), "vector database");
  assert.equal(repairTypos("vector database"), null);
  const a = publicAttempts("vectr databse in rust");
  assert.ok(a.some((q) => q.includes("vector database")));
  assert.ok(a[0].includes("language:rust") && a[0].includes("in:name,description,readme"));
  assert.ok(publicAttempts("cli tools by sharkdp")[0].includes("user:sharkdp"));
});
