import { test } from "node:test";
import assert from "node:assert/strict";

process.env.GITHUB_TOKEN ??= "test-token";

// Fake GitHub REST: routes keyed by "METHOD path" (query string dropped).
type Reply = { status?: number; body?: unknown; headers?: Record<string, string> };
const routes = new Map<string, Reply | ((body: any) => Reply)>();
const calls: string[] = [];
let scopesHeader = "repo, read:user";

globalThis.fetch = (async (url: string, init: { method?: string; body?: string } = {}) => {
  const u = new URL(url);
  const key = `${init.method ?? "GET"} ${u.pathname}`;
  calls.push(key);
  const r = routes.get(key);
  const reply = typeof r === "function" ? r(init.body ? JSON.parse(init.body) : undefined) : r;
  if (!reply) return new Response(JSON.stringify({ message: "Not Found" }), { status: 404 });
  return new Response(reply.status === 204 ? null : JSON.stringify(reply.body ?? {}), {
    status: reply.status ?? 200,
    headers: { "x-oauth-scopes": scopesHeader, "x-ratelimit-remaining": "4999", "x-ratelimit-limit": "5000", ...(reply.headers ?? {}) },
  });
}) as unknown as typeof fetch;

const { computeCan, readPermissions, roleOf, REASONS } = await import("../src/github/perms.js");
const { mapWriteError, missingWriteScope } = await import("../src/github/client.js");
const detail = await import("../src/github/detail.js");
const actions = await import("../src/github/actions.js");
const { activityItem } = await import("../src/github/events.js");

const user = (login: string) => ({ login, avatar_url: `https://a/${login}`, html_url: `https://github.com/${login}` });
const base = {
  kind: "pr" as const,
  state: "open",
  writable: true,
  scopes: ["repo"],
  perms: readPermissions({ pull: true, triage: true, push: true }),
  viewer: "nick",
  author: "ana",
  locked: false,
  archived: false,
  isPrivate: true,
  mergeable: true,
  mergeableState: "clean",
};

// ---- permissions ----------------------------------------------------------------

test("a writer may do everything on someone else's open pull request", () => {
  const { can, why } = computeCan(base);
  for (const k of ["comment", "review", "approve", "merge", "close", "label", "assign", "edit"] as const) assert.equal(can[k], true, k);
  assert.equal(can.reopen, false);
  assert.equal(can.markReady, false);
  assert.equal(why.merge, undefined);
});

test("no write access without a connected account, with a reason", () => {
  const { can, why } = computeCan({ ...base, writable: false });
  assert.ok(Object.values(can).every((v) => v === false));
  assert.equal(why.comment, REASONS.notConnected);
});

test("a classic token without repo scope must reconnect", () => {
  const { can, why } = computeCan({ ...base, scopes: ["read:user"] });
  assert.equal(can.comment, false);
  assert.equal(why.merge, REASONS.scope);
  // public_repo is enough on a public repository; fine-grained tokens (null) rely on permissions.
  assert.equal(computeCan({ ...base, scopes: ["public_repo"], isPrivate: false }).can.merge, true);
  assert.equal(computeCan({ ...base, scopes: null }).can.merge, true);
  assert.equal(missingWriteScope(["public_repo"], true), true);
  assert.equal(missingWriteScope(null, true), false);
});

test("readers comment and review but cannot merge, label or close others' items", () => {
  const { can, why } = computeCan({ ...base, perms: readPermissions({ pull: true }) });
  assert.equal(can.comment, true);
  assert.equal(can.review, true);
  assert.equal(can.approve, true);
  assert.equal(can.merge, false);
  assert.equal(why.merge, REASONS.write);
  assert.equal(can.label, false);
  assert.equal(why.label, REASONS.triage);
  assert.equal(can.close, false);
  assert.equal(can.edit, false);
});

test("the author closes and edits their own item but cannot approve it", () => {
  const { can, why } = computeCan({ ...base, perms: readPermissions({ pull: true }), viewer: "Ana" });
  assert.equal(can.close, true);
  assert.equal(can.edit, true);
  assert.equal(can.approve, false);
  assert.equal(why.approve, REASONS.ownPr);
});

test("drafts, conflicts, protection and merged state gate merging", () => {
  const draft = computeCan({ ...base, state: "draft" });
  assert.equal(draft.can.merge, false);
  assert.equal(draft.why.merge, REASONS.draft);
  assert.equal(draft.can.markReady, true);
  assert.equal(computeCan({ ...base, mergeable: false, mergeableState: "dirty" }).why.merge, REASONS.conflicts);
  assert.equal(computeCan({ ...base, mergeableState: "blocked" }).why.merge, REASONS.blocked);
  assert.equal(computeCan({ ...base, mergeableState: "blocked", perms: readPermissions({ admin: true }) }).can.merge, true);
  const merged = computeCan({ ...base, state: "merged" });
  assert.equal(merged.can.merge, false);
  assert.equal(merged.can.reopen, false);
  assert.equal(merged.why.reopen, REASONS.merged);
});

test("archived repositories and locked conversations", () => {
  assert.equal(computeCan({ ...base, archived: true }).why.comment, REASONS.archived);
  const locked = computeCan({ ...base, locked: true, perms: readPermissions({ pull: true }) });
  assert.equal(locked.can.comment, false);
  assert.equal(locked.why.comment, REASONS.locked);
  // Writers may still talk on a locked thread.
  assert.equal(computeCan({ ...base, locked: true }).can.comment, true);
});

test("issues: no review or merge keys, reopen when closed", () => {
  const { can, why } = computeCan({ ...base, kind: "issue", state: "closed" });
  assert.equal(can.reopen, true);
  assert.equal(can.close, false);
  assert.equal(can.merge, false);
  assert.equal(why.merge, undefined);
});

test("roles from repository permissions", () => {
  assert.equal(roleOf(readPermissions({ admin: true })), "admin");
  assert.equal(roleOf(readPermissions({ push: true, pull: true })), "write");
  assert.equal(roleOf(readPermissions({ triage: true, pull: true })), "triage");
  assert.equal(roleOf(readPermissions({ pull: true })), "read");
  assert.equal(roleOf(readPermissions(undefined)), null);
});

// ---- error mapping ---------------------------------------------------------------

test("write errors map to typed codes", () => {
  assert.equal(mapWriteError(403, "Must have admin rights", null, ["read:user"], "repo").code, "github_scope_missing");
  assert.equal(mapWriteError(403, "Resource not accessible by personal access token", null, null, null).code, "github_scope_missing");
  assert.equal(mapWriteError(403, "Must have push access", null, ["repo"], "repo").code, "github_no_permission");
  assert.equal(mapWriteError(404, "Not Found", null, ["repo"], "").code, "github_no_permission");
  assert.equal(mapWriteError(422, "Validation Failed", null).code, "github_invalid");
  assert.equal(mapWriteError(405, "Pull Request is not mergeable", null).code, "github_not_mergeable");
  assert.equal(mapWriteError(409, "Head branch was modified", null).status, 409);
  const rl = mapWriteError(403, "API rate limit exceeded", { limit: 5000, remaining: 0, resetsAt: "2026-01-01T10:20:00Z", resource: "core" });
  assert.equal(rl.code, "rate_limited");
  assert.equal(rl.retryable, true);
});

// ---- timeline ---------------------------------------------------------------------

test("timeline: review comments nest under their review, noise is dropped, oldest first", () => {
  const items = detail.buildTimeline(
    [
      { event: "reviewed", id: 9, user: user("bo"), state: "CHANGES_REQUESTED", body: "Needs tests", submitted_at: "2026-01-03T00:00:00Z", html_url: "r" },
      { event: "commented", id: 1, user: user("ana"), body: "LGTM?", created_at: "2026-01-02T00:00:00Z", html_url: "c", reactions: { "+1": 2, heart: 0 } },
      { event: "labeled", id: 2, actor: user("ana"), label: { name: "bug", color: "d73a4a" }, created_at: "2026-01-01T00:00:00Z" },
      { event: "subscribed", id: 3, actor: user("ana"), created_at: "2026-01-01T00:00:00Z" },
      { event: "committed", sha: "abc1234def", message: "fix: thing\n\nmore", author: { name: "Ana", date: "2026-01-01T12:00:00Z" }, html_url: "x" },
      { event: "head_ref_force_pushed", id: 4, actor: user("ana"), created_at: "2026-01-04T00:00:00Z" },
      { event: "renamed", id: 5, actor: user("ana"), rename: { from: "a", to: "b" }, created_at: "2026-01-04T01:00:00Z" },
      { event: "merged", id: 6, actor: user("bo"), commit_id: "fedcba9876", created_at: "2026-01-05T00:00:00Z" },
    ],
    [
      { id: 100, pull_request_review_id: 9, path: "lib/a.dart", line: 12, diff_hunk: "@@ -1 +1 @@", body: "here", user: user("bo"), created_at: "2026-01-03T00:00:00Z" },
      { id: 101, pull_request_review_id: 77, path: "lib/b.dart", original_line: 4, body: "orphan", user: user("bo"), created_at: "2026-01-03T05:00:00Z" },
    ],
  );
  assert.deepEqual(
    items.map((i) => i.event),
    ["labeled", "committed", "commented", "reviewed", "review_comment", "head_ref_force_pushed", "renamed", "merged"],
  );
  const review = items.find((i) => i.kind === "review")!;
  assert.equal(review.state, "changes_requested");
  assert.equal(review.comments?.length, 1);
  assert.equal(review.comments?.[0].path, "lib/a.dart");
  assert.equal(items.find((i) => i.event === "commented")!.reactions?.["+1"], 2);
  assert.equal(items.find((i) => i.event === "committed")!.detail, "fix: thing");
  assert.equal(items.find((i) => i.event === "renamed")!.detail, "a → b");
  assert.equal(items.find((i) => i.event === "merged")!.detail, "fedcba9");
  assert.equal(items.find((i) => i.event === "review_comment")!.comments?.[0].line, 4);
});

test("check states", () => {
  assert.equal(detail.checkStatus("completed", "success"), "pass");
  assert.equal(detail.checkStatus("completed", "timed_out"), "fail");
  assert.equal(detail.checkStatus("in_progress", null), "pending");
  assert.equal(detail.checkStatus("completed", "skipped"), "skipped");
  assert.equal(detail.statusState("error"), "fail");
  assert.equal(detail.statusState("pending"), "pending");
});

// ---- service against a fake GitHub --------------------------------------------------

const PR = {
  number: 12,
  title: "Add checks tab",
  state: "open",
  draft: false,
  body: "Body **md**",
  html_url: "https://github.com/o/r/pull/12",
  node_id: "PR_1",
  user: user("ana"),
  labels: [{ name: "feature", color: "1f883d", description: "New" }],
  assignees: [user("nick")],
  requested_reviewers: [user("bo")],
  requested_teams: [{ name: "core" }],
  milestone: { title: "v1.2", number: 3, due_on: null, state: "open", html_url: "m" },
  head: { ref: "feat/checks", sha: "a".repeat(40), repo: { full_name: "o/r" } },
  base: { ref: "main" },
  mergeable: true,
  mergeable_state: "clean",
  comments: 2,
  review_comments: 1,
  commits: 3,
  additions: 40,
  deletions: 4,
  changed_files: 2,
  created_at: "2026-01-01T00:00:00Z",
  updated_at: "2026-01-02T00:00:00Z",
};

routes.set("GET /repos/o/r", { body: { full_name: "o/r", private: true, archived: false, permissions: { admin: false, maintain: false, push: true, triage: true, pull: true }, allow_rebase_merge: false } });
routes.set("GET /user", { body: { login: "nick" } });
routes.set("GET /repos/o/r/pulls/12", { body: PR });
routes.set("GET /repos/o/r/issues/5", { body: { number: 5, title: "Bug", state: "closed", state_reason: "not_planned", user: user("nick"), labels: [], assignees: [], html_url: "i", reactions: { heart: 3 } } });
routes.set(`GET /repos/o/r/commits/${"a".repeat(40)}/check-runs`, {
  body: { check_runs: [{ name: "test", status: "completed", conclusion: "failure", html_url: "h", app: { name: "Actions" }, output: { title: "2 failed" } }, { name: "lint", status: "completed", conclusion: "success" }] },
});
routes.set(`GET /repos/o/r/commits/${"a".repeat(40)}/status`, { body: { state: "pending", statuses: [{ context: "deploy", state: "pending", description: "Waiting" }] } });

test("pull detail: header fields, merge methods and what the viewer may do", async () => {
  const d = await detail.pullDetail("o", "r", 12);
  assert.equal(d.state, "open");
  assert.equal(d.head, "feat/checks");
  assert.equal(d.milestone?.title, "v1.2");
  assert.deepEqual(d.requestedTeams, ["core"]);
  assert.equal(d.labels[0].description, "New");
  assert.equal(d.comments, 3);
  assert.deepEqual(d.mergeMethods, { merge: true, squash: true, rebase: false });
  assert.equal(d.viewer.login, "nick");
  assert.equal(d.viewer.role, "write");
  assert.equal(d.viewer.isAuthor, false);
  assert.equal(d.can.merge, true);
  assert.equal(d.can.approve, true);
  assert.equal(d.viewer.needsReconnect, false);
});

test("issue detail: closed as not planned, reopen allowed for the author", async () => {
  const d = await detail.issueDetail("o", "r", 5);
  assert.equal(d.state, "closed");
  assert.equal(d.stateReason, "not_planned");
  assert.equal(d.viewer.isAuthor, true);
  assert.equal(d.can.reopen, true);
  assert.deepEqual(d.reactions, { heart: 3 });
});

test("checks: failures first with a summary", async () => {
  const c = await detail.pullChecks("o", "r", 12);
  assert.equal(c.overall, "fail");
  assert.deepEqual(c.summary, { pass: 1, fail: 1, pending: 1, skipped: 0, total: 3 });
  assert.equal(c.items[0].name, "test");
  assert.equal(c.items[0].detail, "2 failed");
  assert.equal(c.unavailable, null);
});

test("writes send the right payload and drop the repository's cached reads", async () => {
  let sent: any;
  routes.set("POST /repos/o/r/issues/12/comments", (b) => {
    sent = b;
    return { status: 201, body: { id: 1, body: b.body, user: user("nick"), html_url: "u" } };
  });
  await detail.pullDetail("o", "r", 12); // cached
  const before = calls.filter((c) => c === "GET /repos/o/r/pulls/12").length;
  const c = await actions.addComment("o", "r", 12, "Looks good");
  assert.deepEqual(sent, { body: "Looks good" });
  assert.equal(c.user?.login, "nick");
  await detail.pullDetail("o", "r", 12);
  assert.equal(calls.filter((x) => x === "GET /repos/o/r/pulls/12").length, before + 1);

  routes.set("PUT /repos/o/r/pulls/12/merge", (b) => {
    sent = b;
    return { body: { merged: true, sha: "b".repeat(40), message: "Pull Request successfully merged" } };
  });
  const m = await actions.mergePull("o", "r", 12, { method: "squash", title: "feat: checks (#12)" });
  assert.equal(m.merged, true);
  assert.deepEqual(sent, { merge_method: "squash", commit_title: "feat: checks (#12)" });

  routes.set("PATCH /repos/o/r/issues/5", (b) => {
    sent = b;
    return { body: { number: 5, title: "Bug", state: "closed", state_reason: "completed", labels: [{ name: "bug", color: "f00" }], assignees: [] } };
  });
  const u = await actions.updateIssue("o", "r", 5, { state: "closed", stateReason: "completed", labels: ["bug", "bug"] });
  assert.deepEqual(sent, { state: "closed", state_reason: "completed", labels: ["bug"] });
  assert.equal(u.stateReason, "completed");
});

test("write input is validated before GitHub is called", async () => {
  await assert.rejects(actions.addComment("o", "r", 12, "  "), /empty/);
  await assert.rejects(actions.submitReview("o", "r", 12, { event: "SHIP_IT" }), /Pick approve, request changes or comment/);
  await assert.rejects(actions.submitReview("o", "r", 12, { event: "REQUEST_CHANGES" }), /body is required/);
  await assert.rejects(actions.mergePull("o", "r", 12, { method: "octopus" }), /method must be/);
  await assert.rejects(actions.updateIssue("o", "r", 5, {}), /Nothing to change/);
  await assert.rejects(actions.react("o", "r", 5, "party"), /Unknown reaction/);
  await assert.rejects(actions.addComment("o", "r", 0, "x"), /Invalid number/);
});

test("a refused write comes back typed: missing scope asks to reconnect", async () => {
  scopesHeader = "read:user";
  routes.set("POST /repos/o/r/pulls/12/reviews", { status: 403, body: { message: "Must have admin rights to Repository." }, headers: { "x-accepted-oauth-scopes": "repo" } });
  await assert.rejects(actions.submitReview("o", "r", 12, { event: "APPROVE" }), (e: any) => e.code === "github_scope_missing" && e.status === 403);
  scopesHeader = "repo, read:user";
  routes.set("PUT /repos/o/r/pulls/12/merge", { status: 405, body: { message: "Pull Request is not mergeable" } });
  await assert.rejects(actions.mergePull("o", "r", 12, {}), (e: any) => e.code === "github_not_mergeable");
});

// ---- activity ---------------------------------------------------------------------------

test("activity items know what to open", () => {
  const push = activityItem({
    id: "1",
    type: "PushEvent",
    repo: { name: "o/r" },
    created_at: "2026-01-01T00:00:00Z",
    payload: { ref: "refs/heads/main", head: "c2", size: 2, commits: [{ sha: "c1", message: "first" }, { sha: "c2", message: "second\nbody" }] },
  });
  assert.equal(push.type, "push");
  assert.equal(push.ref, "main");
  assert.equal(push.sha, "c2");
  assert.equal(push.title, "second");
  assert.deepEqual(push.commits.map((c) => c.sha), ["c2", "c1"]);

  const slim = activityItem({ id: "1b", type: "PushEvent", repo: { name: "o/r" }, payload: { ref: "refs/heads/dev", head: "d1" } });
  assert.equal(slim.sha, "d1");
  assert.match(slim.title, /dev/);

  const merged = activityItem({ id: "2", type: "PullRequestEvent", repo: { name: "o/r" }, payload: { action: "closed", number: 7, pull_request: { number: 7, title: "T", merged: true } } });
  assert.equal(merged.action, "merged");
  assert.equal(merged.isPr, true);
  assert.equal(merged.number, 7);

  const comment = activityItem({ id: "3", type: "IssueCommentEvent", repo: { name: "o/r" }, payload: { action: "created", issue: { number: 4, title: "I", pull_request: {} }, comment: { body: "hi" } } });
  assert.equal(comment.isPr, true);
  assert.equal(comment.body, "hi");

  const rel = activityItem({ id: "4", type: "ReleaseEvent", repo: { name: "o/r" }, payload: { action: "published", release: { tag_name: "v1", name: "", body: "notes" } } });
  assert.equal(rel.release?.tag, "v1");
  assert.equal(rel.title, "v1");

  const review = activityItem({ id: "5", type: "PullRequestReviewEvent", repo: { name: "o/r" }, payload: { review: { state: "APPROVED" }, pull_request: { number: 9, title: "P" } } });
  assert.equal(review.action, "approved");
  assert.equal(review.number, 9);
});
