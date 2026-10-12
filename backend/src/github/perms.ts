/**
 * What the caller may do on one pull request or issue. GitHub only answers
 * "no" after the fact, so the app asks first: from the repository's
 * `permissions` (admin / maintain / push / triage / pull), the token's OAuth
 * scopes, whether the viewer wrote the item, and its state. Every `false`
 * comes with a short reason the app shows next to the disabled action.
 */

export type RepoPermissions = { admin: boolean; maintain: boolean; push: boolean; triage: boolean; pull: boolean };

export type Can = {
  comment: boolean;
  react: boolean;
  /** Leave a review (comment review). */
  review: boolean;
  /** Approve or request changes (not on your own pull request). */
  approve: boolean;
  merge: boolean;
  close: boolean;
  reopen: boolean;
  label: boolean;
  assign: boolean;
  edit: boolean;
  markReady: boolean;
};

export type CanKey = keyof Can;

export type PermInput = {
  kind: "pr" | "issue";
  /** open | draft | closed | merged */
  state: string;
  /** The caller's token may write at all (own account, or the owner on the server token). */
  writable: boolean;
  /** OAuth scopes of a classic token; null for fine-grained tokens / unknown. */
  scopes: string[] | null;
  /** `permissions` of GET /repos/:o/:r; null when GitHub did not send them. */
  perms: RepoPermissions | null;
  viewer: string | null;
  author: string | null;
  locked: boolean;
  archived: boolean;
  isPrivate: boolean;
  /** Pull requests: GitHub's mergeable flag (null while it computes). */
  mergeable?: boolean | null;
  /** Pull requests: mergeable_state (clean, dirty, blocked, behind, unstable, draft, unknown). */
  mergeableState?: string | null;
};

export const REASONS = {
  notConnected: "Connect your GitHub account to make changes",
  scope: "Your GitHub token can't write here. Reconnect GitHub with repo access",
  archived: "This repository is archived (read-only)",
  locked: "The conversation is locked",
  readOnly: "You have read-only access to this repository",
  triage: "Needs triage access to this repository",
  write: "Needs write access to this repository",
  ownPr: "You can't approve your own pull request",
  notOpen: "Only open pull requests",
  draft: "Mark it ready for review first",
  conflicts: "This branch has conflicts to resolve first",
  blocked: "Merging is blocked by branch protection (reviews or checks)",
  merged: "Already merged",
  notDraft: "Already ready for review",
  editOwn: "Only the author or maintainers can edit",
} as const;

const KEYS: CanKey[] = ["comment", "react", "review", "approve", "merge", "close", "reopen", "label", "assign", "edit", "markReady"];

export function readPermissions(p: unknown): RepoPermissions | null {
  if (!p || typeof p !== "object") return null;
  const o = p as Record<string, unknown>;
  const b = (k: string) => o[k] === true;
  return { admin: b("admin"), maintain: b("maintain") || b("admin"), push: b("push") || b("admin"), triage: b("triage") || b("push") || b("admin"), pull: b("pull") || b("push") || b("admin") };
}

/** The highest role in [p], as GitHub names it. */
export function roleOf(p: RepoPermissions | null): "admin" | "maintain" | "write" | "triage" | "read" | null {
  if (!p) return null;
  if (p.admin) return "admin";
  if (p.maintain) return "maintain";
  if (p.push) return "write";
  if (p.triage) return "triage";
  return p.pull ? "read" : null;
}

export function computeCan(i: PermInput): { can: Can; why: Partial<Record<CanKey, string>> } {
  const can = Object.fromEntries(KEYS.map((k) => [k, false])) as Can;
  const why: Partial<Record<CanKey, string>> = {};
  const deny = (k: CanKey, reason: string) => {
    can[k] = false;
    why[k] ??= reason;
  };
  const allow = (k: CanKey) => {
    can[k] = true;
    delete why[k];
  };
  const all = (reason: string) => {
    for (const k of KEYS) deny(k, reason);
    return { can, why };
  };

  if (!i.writable) return all(REASONS.notConnected);
  if (i.scopes != null && !i.scopes.includes("repo") && (i.isPrivate || !i.scopes.includes("public_repo"))) return all(REASONS.scope);
  if (i.archived) return all(REASONS.archived);

  const isAuthor = !!i.viewer && !!i.author && i.viewer.toLowerCase() === i.author.toLowerCase();
  // Unknown permissions (GitHub sent none): assume a reader on public repos.
  const p = i.perms ?? { admin: false, maintain: false, push: false, triage: false, pull: !i.isPrivate };
  const pr = i.kind === "pr";
  const merged = i.state === "merged";
  const open = i.state === "open" || i.state === "draft";

  // Conversation: anyone who can read may comment, unless it is locked.
  if (i.locked && !p.push) {
    deny("comment", REASONS.locked);
    deny("react", REASONS.locked);
  } else if (p.pull) {
    allow("comment");
    allow("react");
  } else {
    deny("comment", REASONS.readOnly);
    deny("react", REASONS.readOnly);
  }

  // Reviews.
  if (pr) {
    if (!open) {
      deny("review", REASONS.notOpen);
      deny("approve", merged ? REASONS.merged : REASONS.notOpen);
    } else if (!can.comment) {
      deny("review", why.comment ?? REASONS.readOnly);
      deny("approve", why.comment ?? REASONS.readOnly);
    } else {
      allow("review");
      if (isAuthor) deny("approve", REASONS.ownPr);
      else allow("approve");
    }
  }

  // Merge.
  if (pr) {
    if (merged) deny("merge", REASONS.merged);
    else if (!open) deny("merge", REASONS.notOpen);
    else if (!p.push) deny("merge", REASONS.write);
    else if (i.state === "draft") deny("merge", REASONS.draft);
    else if (i.mergeable === false || i.mergeableState === "dirty") deny("merge", REASONS.conflicts);
    else if (i.mergeableState === "blocked" && !p.admin) deny("merge", REASONS.blocked);
    else allow("merge");
  }

  // State: triage+ or the author.
  const triage = p.triage || isAuthor;
  if (open) {
    if (triage) allow("close");
    else deny("close", REASONS.triage);
    deny("reopen", REASONS.notOpen);
  } else {
    deny("close", REASONS.notOpen);
    if (merged) deny("reopen", REASONS.merged);
    else if (triage) allow("reopen");
    else deny("reopen", REASONS.triage);
  }

  // Labels and assignees: triage+.
  for (const k of ["label", "assign"] as const) {
    if (p.triage) allow(k);
    else deny(k, REASONS.triage);
  }

  // Title / body: the author or anyone with write access.
  if (isAuthor || p.push) allow("edit");
  else deny("edit", REASONS.editOwn);

  // Draft to ready.
  if (!pr || i.state !== "draft") deny("markReady", REASONS.notDraft);
  else if (isAuthor || p.push) allow("markReady");
  else deny("markReady", REASONS.write);

  if (!pr) {
    for (const k of ["review", "approve", "merge", "markReady"] as const) delete why[k];
  }
  return { can, why };
}
