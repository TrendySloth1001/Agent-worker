import { AppError } from "../util/errors.js";
import { canWriteWith, gh, ghAuth, tokenScopes } from "./client.js";
import { computeCan, readPermissions, roleOf, type RepoPermissions } from "./perms.js";
import { checkName, repoRaw } from "./service.js";

/**
 * Pull request and issue detail for the app's in-app screens: the header,
 * the conversation timeline (comments, reviews with their inline comments,
 * and events), commits, files, checks, and what the viewer may do (`can`).
 */

const DETAIL_TTL = 30_000;
const BODY_MAX = 20_000;
const COMMENT_MAX = 8_000;
const TIMELINE_PAGES = 3;
const PATCH_MAX = 40_000;
const FILES_MAX = 300;

const clip = (s: string | null | undefined, n: number) => {
  const t = (s ?? "").replace(/\r/g, "").trim();
  return t.length > n ? `${t.slice(0, n).trimEnd()}…` : t;
};

export type GhUserLite = { login: string; avatar: string; url: string } | null;
export const userOf = (u: any): GhUserLite => (u?.login ? { login: u.login, avatar: u.avatar_url ?? "", url: u.html_url ?? `https://github.com/${u.login}` } : null);
const users = (us: any[] | undefined) => (us ?? []).map(userOf).filter((u): u is NonNullable<GhUserLite> => !!u);
export const labelOf = (l: any) => ({ name: String(l?.name ?? l ?? ""), color: String(l?.color ?? ""), description: String(l?.description ?? "") });
const labelList = (ls: any[] | undefined) => (ls ?? []).map(labelOf).filter((l) => l.name);
const milestoneOf = (m: any) => (m?.title ? { title: String(m.title), number: m.number ?? null, dueOn: m.due_on ?? null, state: m.state ?? "open", url: m.html_url ?? "" } : null);

function checkNumber(n: number) {
  if (!Number.isInteger(n) || n <= 0) throw new AppError(400, "bad_request", "Invalid number");
}

/** Login of whoever the token belongs to (null if unknown). */
export async function viewerLogin(signal?: AbortSignal): Promise<string | null> {
  const auth = await ghAuth();
  if (auth.login) return auth.login;
  if (!auth.token) return null;
  const u = await gh(`/user`, { ttlMs: 10 * 60_000, signal }).catch(() => null);
  return (u?.login as string | undefined) ?? null;
}

/** The viewer block and `can` of one item. */
async function access(repo: any, item: { kind: "pr" | "issue"; state: string; author: string | null; locked: boolean; mergeable?: boolean | null; mergeableState?: string | null }) {
  const auth = await ghAuth();
  const [login, scopes] = await Promise.all([viewerLogin(), tokenScopes()]);
  const perms: RepoPermissions | null = readPermissions(repo?.permissions);
  const writable = canWriteWith(auth);
  const { can, why } = computeCan({
    ...item,
    writable,
    scopes,
    perms,
    viewer: login,
    isPrivate: !!repo?.private,
    archived: !!repo?.archived,
  });
  return {
    can,
    why,
    viewer: {
      login,
      role: roleOf(perms),
      isAuthor: !!login && !!item.author && login.toLowerCase() === item.author.toLowerCase(),
      canWrite: writable,
      scopes,
      tokenKind: scopes == null ? "fine-grained" : "classic",
      /** The token lacks the scope to write here: the app offers Reconnect. */
      needsReconnect: writable && scopes != null && !scopes.includes("repo") && (!!repo?.private || !scopes.includes("public_repo")),
    },
  };
}

export function prState(p: any): string {
  if (p.merged || p.merged_at) return "merged";
  if (p.state === "open" && p.draft) return "draft";
  return p.state === "closed" ? "closed" : "open";
}

/** The pull request header plus what the viewer may do. */
export async function pullDetail(owner: string, repo: string, n: number) {
  checkName(owner, repo);
  checkNumber(n);
  const [p, r] = await Promise.all([gh(`/repos/${owner}/${repo}/pulls/${n}`, { ttlMs: DETAIL_TTL }), repoRaw(owner, repo)]);
  const state = prState(p);
  const author = p.user?.login ?? null;
  const acc = await access(r, { kind: "pr", state, author, locked: !!p.locked, mergeable: p.mergeable ?? null, mergeableState: p.mergeable_state ?? null });
  return {
    repo: r.full_name as string,
    number: p.number as number,
    title: String(p.title ?? ""),
    state,
    isPr: true,
    body: clip(p.body, BODY_MAX),
    url: p.html_url as string,
    user: userOf(p.user),
    authorAssociation: p.author_association ?? null,
    labels: labelList(p.labels),
    assignees: users(p.assignees),
    requestedReviewers: users(p.requested_reviewers),
    requestedTeams: (p.requested_teams ?? []).map((t: any) => String(t?.name ?? t?.slug ?? "")).filter(Boolean),
    milestone: milestoneOf(p.milestone),
    head: p.head?.ref ?? "",
    headRepo: p.head?.repo?.full_name ?? null,
    headSha: p.head?.sha ?? "",
    base: p.base?.ref ?? "",
    createdAt: p.created_at ?? null,
    updatedAt: p.updated_at ?? null,
    closedAt: p.closed_at ?? null,
    mergedAt: p.merged_at ?? null,
    mergedBy: userOf(p.merged_by),
    commits: p.commits ?? 0,
    additions: p.additions ?? 0,
    deletions: p.deletions ?? 0,
    changedFiles: p.changed_files ?? 0,
    comments: (p.comments ?? 0) + (p.review_comments ?? 0),
    locked: !!p.locked,
    mergeable: p.mergeable ?? null,
    mergeableState: p.mergeable_state ?? null,
    rebaseable: p.rebaseable ?? null,
    mergeMethods: {
      merge: r.allow_merge_commit !== false,
      squash: r.allow_squash_merge !== false,
      rebase: r.allow_rebase_merge !== false,
    },
    ...acc,
  };
}

/** The issue header plus what the viewer may do. A pull request number answers 404. */
export async function issueDetail(owner: string, repo: string, n: number) {
  checkName(owner, repo);
  checkNumber(n);
  const [i, r] = await Promise.all([gh(`/repos/${owner}/${repo}/issues/${n}`, { ttlMs: DETAIL_TTL }), repoRaw(owner, repo)]);
  if (i.pull_request) throw new AppError(404, "not_found", "That number is a pull request");
  const state = i.state === "closed" ? "closed" : "open";
  const author = i.user?.login ?? null;
  const acc = await access(r, { kind: "issue", state, author, locked: !!i.locked });
  return {
    repo: r.full_name as string,
    number: i.number as number,
    title: String(i.title ?? ""),
    state,
    stateReason: i.state_reason ?? null,
    isPr: false,
    body: clip(i.body, BODY_MAX),
    url: i.html_url as string,
    user: userOf(i.user),
    authorAssociation: i.author_association ?? null,
    labels: labelList(i.labels),
    assignees: users(i.assignees),
    milestone: milestoneOf(i.milestone),
    comments: i.comments ?? 0,
    createdAt: i.created_at ?? null,
    updatedAt: i.updated_at ?? null,
    closedAt: i.closed_at ?? null,
    closedBy: userOf(i.closed_by),
    locked: !!i.locked,
    reactions: reactionsOf(i.reactions),
    ...acc,
  };
}

const REACTIONS = ["+1", "-1", "laugh", "hooray", "confused", "heart", "rocket", "eyes"] as const;
export type Reaction = (typeof REACTIONS)[number];
export const isReaction = (s: unknown): s is Reaction => typeof s === "string" && (REACTIONS as readonly string[]).includes(s);
const reactionsOf = (r: any) => Object.fromEntries(REACTIONS.map((k) => [k, Number(r?.[k] ?? 0)]).filter(([, v]) => (v as number) > 0));

// ---- timeline ----------------------------------------------------------------

export type ReviewComment = {
  id: number;
  reviewId: number | null;
  inReplyTo: number | null;
  path: string;
  line: number | null;
  diffHunk: string;
  body: string;
  user: GhUserLite;
  at: string | null;
  url: string;
};

export type TimelineItem = {
  kind: "comment" | "review" | "commit" | "event";
  id: string;
  at: string | null;
  actor: GhUserLite;
  /** Raw GitHub event name (labeled, closed, merged, head_ref_force_pushed, …). */
  event: string;
  body?: string;
  /** Review: approved | changes_requested | commented | dismissed. */
  state?: string;
  label?: { name: string; color: string };
  /** Short human detail: renamed from → to, the assignee, the commit sha, … */
  detail?: string;
  sha?: string;
  url?: string;
  reactions?: Record<string, number>;
  comments?: ReviewComment[];
};

export const reviewCommentOf = (c: any): ReviewComment => ({
  id: Number(c.id),
  reviewId: c.pull_request_review_id ?? null,
  inReplyTo: c.in_reply_to_id ?? null,
  path: String(c.path ?? ""),
  line: c.line ?? c.original_line ?? null,
  diffHunk: clip(c.diff_hunk, 2_000),
  body: clip(c.body, COMMENT_MAX),
  user: userOf(c.user),
  at: c.created_at ?? null,
  url: c.html_url ?? "",
});

const SKIP = new Set(["subscribed", "unsubscribed", "mentioned", "comment_deleted", "line-commented", "commit-commented", "added_to_project", "moved_columns_in_project", "removed_from_project", "converted_note_to_issue", "pinned", "unpinned", "transferred"]);

/** One GitHub timeline event as an app item (null for noise). */
export function timelineItem(e: any): TimelineItem | null {
  const ev = String(e?.event ?? "");
  if (!ev || SKIP.has(ev)) return null;
  const actor = userOf(e.actor ?? e.user ?? e.author);
  const at = e.created_at ?? e.submitted_at ?? e.author?.date ?? e.committer?.date ?? null;
  const id = String(e.id ?? e.node_id ?? e.sha ?? `${ev}-${at}`);
  switch (ev) {
    case "commented":
      return { kind: "comment", id, at, actor: userOf(e.user ?? e.actor), event: ev, body: clip(e.body, COMMENT_MAX), url: e.html_url, reactions: reactionsOf(e.reactions) };
    case "reviewed":
      return { kind: "review", id, at: e.submitted_at ?? at, actor: userOf(e.user ?? e.actor), event: ev, state: String(e.state ?? "commented").toLowerCase(), body: clip(e.body, COMMENT_MAX), url: e.html_url, comments: [] };
    case "committed":
      return {
        kind: "commit",
        id: String(e.sha ?? id),
        at: e.author?.date ?? e.committer?.date ?? null,
        actor: null,
        event: ev,
        sha: e.sha,
        detail: String(e.message ?? "").split("\n")[0].slice(0, 200),
        body: String(e.author?.name ?? ""),
        url: e.html_url,
      };
    case "labeled":
    case "unlabeled":
      return { kind: "event", id, at, actor, event: ev, label: { name: String(e.label?.name ?? ""), color: String(e.label?.color ?? "") } };
    case "assigned":
    case "unassigned":
      return { kind: "event", id, at, actor, event: ev, detail: e.assignee?.login ?? "" };
    case "review_requested":
    case "review_request_removed":
      return { kind: "event", id, at, actor, event: ev, detail: e.requested_reviewer?.login ?? e.requested_team?.name ?? "" };
    case "renamed":
      return { kind: "event", id, at, actor, event: ev, detail: `${e.rename?.from ?? ""} → ${e.rename?.to ?? ""}` };
    case "milestoned":
    case "demilestoned":
      return { kind: "event", id, at, actor, event: ev, detail: e.milestone?.title ?? "" };
    case "merged":
    case "referenced":
      return { kind: "event", id, at, actor, event: ev, sha: e.commit_id ?? undefined, detail: e.commit_id ? String(e.commit_id).slice(0, 7) : undefined };
    case "closed":
      return { kind: "event", id, at, actor, event: ev, detail: e.state_reason ?? undefined, sha: e.commit_id ?? undefined };
    case "cross-referenced": {
      const src = e.source?.issue;
      if (!src) return null;
      return { kind: "event", id, at, actor, event: ev, detail: `${src.repository?.full_name ?? ""}#${src.number} ${src.title ?? ""}`.trim(), url: src.html_url };
    }
    case "head_ref_force_pushed":
    case "head_ref_deleted":
    case "head_ref_restored":
    case "reopened":
    case "ready_for_review":
    case "convert_to_draft":
    case "locked":
    case "unlocked":
    case "review_dismissed":
    case "connected":
    case "disconnected":
    case "marked_as_duplicate":
    case "auto_merge_enabled":
    case "auto_merge_disabled":
    case "base_ref_changed":
    case "deployed":
    default:
      return { kind: "event", id, at, actor, event: ev };
  }
}

/** Timeline items with each review's inline comments under it (orphans become their own items), oldest first. */
export function buildTimeline(events: any[], reviewComments: any[]): TimelineItem[] {
  const items = events.map(timelineItem).filter((x): x is TimelineItem => !!x);
  const byReview = new Map<string, TimelineItem>();
  for (const it of items) if (it.kind === "review") byReview.set(it.id, it);
  for (const raw of reviewComments) {
    const c = reviewCommentOf(raw);
    const host = c.reviewId != null ? byReview.get(String(c.reviewId)) : undefined;
    if (host) host.comments!.push(c);
    else items.push({ kind: "comment", id: `rc-${c.id}`, at: c.at, actor: c.user, event: "review_comment", body: c.body, url: c.url, comments: [c] });
  }
  // A review with no body whose comments are all replies is GitHub's "reply" wrapper: keep it, it carries the comments.
  return items
    .filter((it) => !(it.kind === "review" && it.state === "commented" && !it.body && !(it.comments?.length)))
    .sort((a, b) => (a.at ?? "").localeCompare(b.at ?? ""));
}

async function pages(path: string, max = TIMELINE_PAGES): Promise<any[]> {
  const out: any[] = [];
  for (let page = 1; page <= max; page++) {
    const sep = path.includes("?") ? "&" : "?";
    const batch = await gh<any[]>(`${path}${sep}per_page=100&page=${page}`, { ttlMs: DETAIL_TTL });
    if (!Array.isArray(batch)) break;
    out.push(...batch);
    if (batch.length < 100) break;
  }
  return out;
}

/** The conversation of a pull request or issue, oldest first. */
export async function timeline(owner: string, repo: string, n: number, opts: { pr?: boolean } = {}) {
  checkName(owner, repo);
  checkNumber(n);
  const [events, reviewComments] = await Promise.all([
    pages(`/repos/${owner}/${repo}/issues/${n}/timeline`),
    opts.pr ? pages(`/repos/${owner}/${repo}/pulls/${n}/comments`).catch(() => []) : Promise.resolve([]),
  ]);
  const items = buildTimeline(events, reviewComments);
  return { items, truncated: events.length >= TIMELINE_PAGES * 100 };
}

// ---- commits, files, checks ---------------------------------------------------

export async function pullCommits(owner: string, repo: string, n: number) {
  checkName(owner, repo);
  checkNumber(n);
  const list = await pages(`/repos/${owner}/${repo}/pulls/${n}/commits`, 3);
  return {
    items: list.map((c) => ({
      sha: c.sha as string,
      shortSha: String(c.sha).slice(0, 7),
      message: String(c.commit?.message ?? "").split("\n")[0].slice(0, 200),
      author: userOf(c.author),
      authorName: c.commit?.author?.name ?? c.author?.login ?? "",
      date: c.commit?.author?.date ?? c.commit?.committer?.date ?? null,
      url: c.html_url as string,
      verified: !!c.commit?.verification?.verified,
    })),
  };
}

export async function pullFiles(owner: string, repo: string, n: number) {
  checkName(owner, repo);
  checkNumber(n);
  const list = await pages(`/repos/${owner}/${repo}/pulls/${n}/files`, 3);
  return {
    files: list.slice(0, FILES_MAX).map((f) => {
      const patch = typeof f.patch === "string" ? f.patch : null;
      return {
        filename: f.filename as string,
        previousFilename: f.previous_filename ?? null,
        status: f.status as string,
        additions: f.additions ?? 0,
        deletions: f.deletions ?? 0,
        patch: patch ? patch.slice(0, PATCH_MAX) : null,
        patchTruncated: !!patch && patch.length > PATCH_MAX,
        binary: patch == null && (f.changes ?? 0) === 0,
      };
    }),
    filesTruncated: list.length > FILES_MAX,
  };
}

export type CheckItem = { name: string; source: "check" | "status"; status: "pass" | "fail" | "pending" | "skipped" | "neutral"; detail: string; url: string; app: string; at: string | null };

export function checkStatus(status: string | null | undefined, conclusion: string | null | undefined): CheckItem["status"] {
  if (status && status !== "completed") return "pending";
  switch (conclusion) {
    case "success":
      return "pass";
    case "failure":
    case "timed_out":
    case "action_required":
    case "startup_failure":
      return "fail";
    case "cancelled":
    case "skipped":
    case "stale":
      return "skipped";
    case "neutral":
      return "neutral";
    default:
      return "pending";
  }
}

export function statusState(s: string | null | undefined): CheckItem["status"] {
  return s === "success" ? "pass" : s === "failure" || s === "error" ? "fail" : "pending";
}

/** Check runs and commit statuses of a pull request's head commit. */
export async function pullChecks(owner: string, repo: string, n: number) {
  checkName(owner, repo);
  checkNumber(n);
  const p = await gh(`/repos/${owner}/${repo}/pulls/${n}`, { ttlMs: DETAIL_TTL });
  const sha = p.head?.sha as string;
  let unavailable: string | null = null;
  const [runs, combined] = await Promise.all([
    gh(`/repos/${owner}/${repo}/commits/${sha}/check-runs?per_page=100`, { ttlMs: DETAIL_TTL }).catch((e) => {
      if (e instanceof AppError && (e.status === 403 || e.status === 404)) unavailable = "Your GitHub token can't read checks for this repository.";
      else throw e;
      return null;
    }),
    gh(`/repos/${owner}/${repo}/commits/${sha}/status`, { ttlMs: DETAIL_TTL }).catch(() => null),
  ]);
  const items: CheckItem[] = [
    ...((runs?.check_runs ?? []) as any[]).map((c): CheckItem => ({
      name: String(c.name ?? ""),
      source: "check",
      status: checkStatus(c.status, c.conclusion),
      detail: clip(c.output?.title ?? c.conclusion ?? c.status, 200),
      url: c.html_url ?? c.details_url ?? "",
      app: c.app?.name ?? "",
      at: c.completed_at ?? c.started_at ?? null,
    })),
    ...((combined?.statuses ?? []) as any[]).map((s): CheckItem => ({
      name: String(s.context ?? ""),
      source: "status",
      status: statusState(s.state),
      detail: clip(s.description, 200),
      url: s.target_url ?? "",
      app: "",
      at: s.updated_at ?? null,
    })),
  ];
  const order = { fail: 0, pending: 1, pass: 2, neutral: 3, skipped: 4 } as const;
  items.sort((a, b) => order[a.status] - order[b.status] || a.name.localeCompare(b.name));
  const count = (s: CheckItem["status"]) => items.filter((i) => i.status === s).length;
  const summary = { pass: count("pass"), fail: count("fail"), pending: count("pending"), skipped: count("skipped") + count("neutral"), total: items.length };
  const overall = summary.fail ? "fail" : summary.pending ? "pending" : summary.total ? "pass" : "none";
  return { sha, overall, summary, items, unavailable };
}

// ---- pickers --------------------------------------------------------------------

export async function repoLabels(owner: string, repo: string) {
  checkName(owner, repo);
  const list = await pages(`/repos/${owner}/${repo}/labels`, 2);
  return { items: list.map(labelOf) };
}

export async function repoAssignees(owner: string, repo: string) {
  checkName(owner, repo);
  const list = await pages(`/repos/${owner}/${repo}/assignees`, 2);
  return { items: users(list) };
}
