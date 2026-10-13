import { AppError } from "../util/errors.js";
import { canWriteWith, gh, ghAuth, ghGraphql, ghSend } from "./client.js";
import { isReaction, labelOf, prState, userOf } from "./detail.js";
import { checkName } from "./service.js";

/**
 * Changes to pull requests and issues made from the app with the caller's
 * own token. GitHub decides; its refusals come back as typed errors
 * (github_no_permission, github_scope_missing, github_invalid, …).
 */

const TEXT_MAX = 65_000;
const TITLE_MAX = 256;
const LIST_MAX = 100;

function target(owner: string, repo: string, n: number) {
  checkName(owner, repo);
  if (!Number.isInteger(n) || n <= 0) throw new AppError(400, "bad_request", "Invalid number");
}

const text = (v: unknown, field: string, max = TEXT_MAX, required = true): string | undefined => {
  if (v === undefined || v === null) {
    if (required) throw new AppError(400, "bad_request", `${field} is required`);
    return undefined;
  }
  if (typeof v !== "string") throw new AppError(400, "bad_request", `${field} must be text`);
  const t = v.replace(/\r/g, "");
  if (required && !t.trim()) throw new AppError(400, "bad_request", `${field} is empty`);
  if (t.length > max) throw new AppError(400, "bad_request", `${field} is too long`);
  return t;
};

const names = (v: unknown, field: string): string[] | undefined => {
  if (v === undefined) return undefined;
  if (!Array.isArray(v) || v.length > LIST_MAX || v.some((x) => typeof x !== "string" || !x.trim() || x.length > 100)) {
    throw new AppError(400, "bad_request", `${field} must be a list of names`);
  }
  return [...new Set((v as string[]).map((x) => x.trim()))];
};

export async function addComment(owner: string, repo: string, n: number, body: unknown) {
  target(owner, repo, n);
  const c = await ghSend("POST", `/repos/${owner}/${repo}/issues/${n}/comments`, { body: text(body, "body") });
  return { id: c?.id ?? null, url: c?.html_url ?? "", body: String(c?.body ?? ""), user: userOf(c?.user), at: c?.created_at ?? null };
}

const REVIEW_EVENTS = new Set(["APPROVE", "REQUEST_CHANGES", "COMMENT"]);

export async function submitReview(owner: string, repo: string, n: number, input: { event?: unknown; body?: unknown }) {
  target(owner, repo, n);
  const event = String(input.event ?? "").toUpperCase();
  if (!REVIEW_EVENTS.has(event)) throw new AppError(400, "bad_request", "Pick approve, request changes or comment.");
  const body = text(input.body, "body", TEXT_MAX, event !== "APPROVE");
  const r = await ghSend("POST", `/repos/${owner}/${repo}/pulls/${n}/reviews`, { event, ...(body ? { body } : {}) });
  return { id: r?.id ?? null, state: String(r?.state ?? "").toLowerCase(), url: r?.html_url ?? "" };
}

const MERGE_METHODS = new Set(["merge", "squash", "rebase"]);

export async function mergePull(owner: string, repo: string, n: number, input: { method?: unknown; title?: unknown; message?: unknown; sha?: unknown }) {
  target(owner, repo, n);
  const method = String(input.method ?? "merge");
  if (!MERGE_METHODS.has(method)) throw new AppError(400, "bad_request", "method must be merge, squash or rebase");
  const title = text(input.title, "title", TITLE_MAX, false);
  const message = text(input.message, "message", TEXT_MAX, false);
  const sha = typeof input.sha === "string" && /^[0-9a-f]{7,40}$/i.test(input.sha) ? input.sha : undefined;
  const r = await ghSend("PUT", `/repos/${owner}/${repo}/pulls/${n}/merge`, {
    merge_method: method,
    ...(title ? { commit_title: title } : {}),
    ...(message ? { commit_message: message } : {}),
    ...(sha ? { sha } : {}),
  });
  return { merged: r?.merged === true, sha: r?.sha ?? null, message: String(r?.message ?? "") };
}

const STATE_REASONS = new Set(["completed", "not_planned", "reopened"]);

/**
 * Edits an issue or pull request (both through the issues API): state with an
 * optional reason, title, body, labels (replaces them) and assignees.
 */
export async function updateIssue(owner: string, repo: string, n: number, input: Record<string, unknown>) {
  target(owner, repo, n);
  const patch: Record<string, unknown> = {};
  if (input.state !== undefined) {
    if (input.state !== "open" && input.state !== "closed") throw new AppError(400, "bad_request", "state must be open or closed");
    patch.state = input.state;
    if (input.stateReason !== undefined) {
      if (!STATE_REASONS.has(String(input.stateReason))) throw new AppError(400, "bad_request", "stateReason must be completed, not_planned or reopened");
      patch.state_reason = input.stateReason;
    }
  }
  const title = text(input.title, "title", TITLE_MAX, false);
  if (title !== undefined) {
    if (!title.trim()) throw new AppError(400, "bad_request", "title is empty");
    patch.title = title.trim();
  }
  const body = text(input.body, "body", TEXT_MAX, false);
  if (body !== undefined) patch.body = body;
  const labels = names(input.labels, "labels");
  if (labels) patch.labels = labels;
  const assignees = names(input.assignees, "assignees");
  if (assignees) patch.assignees = assignees;
  if (!Object.keys(patch).length) throw new AppError(400, "bad_request", "Nothing to change");
  const i = await ghSend("PATCH", `/repos/${owner}/${repo}/issues/${n}`, patch);
  return {
    number: i?.number ?? n,
    title: String(i?.title ?? ""),
    state: i?.pull_request ? (i.state === "closed" ? "closed" : "open") : i?.state === "closed" ? "closed" : "open",
    stateReason: i?.state_reason ?? null,
    labels: (i?.labels ?? []).map(labelOf),
    assignees: (i?.assignees ?? []).map(userOf).filter(Boolean),
  };
}

export async function react(owner: string, repo: string, n: number, content: unknown) {
  target(owner, repo, n);
  if (!isReaction(content)) throw new AppError(400, "bad_request", "Unknown reaction");
  const r = await ghSend("POST", `/repos/${owner}/${repo}/issues/${n}/reactions`, { content });
  return { id: r?.id ?? null, content };
}

/** Draft → ready for review (GraphQL only). */
export async function markReady(owner: string, repo: string, n: number) {
  target(owner, repo, n);
  if (!canWriteWith(await ghAuth())) throw new AppError(409, "github_not_connected", "Connect your GitHub account to make changes");
  const p = await gh(`/repos/${owner}/${repo}/pulls/${n}`, { ttlMs: 0 });
  if (prState(p) !== "draft") return { state: prState(p) };
  await ghGraphql(`mutation($id: ID!) { markPullRequestReadyForReview(input: { pullRequestId: $id }) { pullRequest { isDraft } } }`, { id: p.node_id });
  // The cached pull request still says draft: read it fresh next time.
  await gh(`/repos/${owner}/${repo}/pulls/${n}`, { ttlMs: 0 }).catch(() => null);
  return { state: "open" };
}
