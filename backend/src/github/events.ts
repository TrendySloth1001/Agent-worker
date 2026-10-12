import { gh, ghAuth } from "./client.js";
import { viewerLogin } from "./detail.js";

/**
 * The connected account's activity feed (GET /users/:login/events, which
 * includes private events for the token's own user), shaped so every item
 * knows which in-app screen it opens: a commit, a pull request, an issue,
 * a release or the repository.
 */

export type ActivityItem = {
  id: string;
  type: "push" | "pr" | "issue" | "review" | "comment" | "release" | "create" | "delete" | "fork" | "star" | "public" | "member" | "other";
  /** opened, closed, merged, reopened, created, published, approved, … */
  action: string;
  repo: string;
  at: string | null;
  title: string;
  number: number | null;
  isPr: boolean;
  sha: string | null;
  ref: string | null;
  url: string;
  commits: { sha: string; message: string }[];
  /** Comment / review / release text (short). */
  body: string;
  release: { tag: string; name: string; prerelease: boolean } | null;
};

const PAGES = 2;
const BODY_MAX = 2_000;

const clip = (s: unknown, n: number) => {
  const t = String(s ?? "").replace(/\r/g, "").trim();
  return t.length > n ? `${t.slice(0, n).trimEnd()}…` : t;
};
const shortRef = (ref: unknown) => String(ref ?? "").replace(/^refs\/(heads|tags)\//, "");

export function activityItem(e: any): ActivityItem {
  const p = e?.payload ?? {};
  const repo = String(e?.repo?.name ?? "");
  const base: ActivityItem = {
    id: String(e?.id ?? ""),
    type: "other",
    action: String(p.action ?? ""),
    repo,
    at: e?.created_at ?? null,
    title: "",
    number: null,
    isPr: false,
    sha: null,
    ref: null,
    url: repo ? `https://github.com/${repo}` : "",
    commits: [],
    body: "",
    release: null,
  };
  switch (e?.type) {
    case "PushEvent": {
      const commits = ((p.commits ?? []) as any[]).map((c) => ({ sha: String(c.sha ?? ""), message: String(c.message ?? "").split("\n")[0].slice(0, 200) })).reverse();
      const ref = shortRef(p.ref);
      const head = String(p.head ?? commits[0]?.sha ?? "");
      const n = Number(p.size ?? p.distinct_size ?? commits.length) || commits.length;
      return {
        ...base,
        type: "push",
        action: "pushed",
        ref,
        sha: head || null,
        title: commits[0]?.message || (n ? `${n} commit${n === 1 ? "" : "s"} to ${ref}` : `Pushed to ${ref}`),
        commits: commits.slice(0, 5),
        url: head ? `https://github.com/${repo}/commit/${head}` : base.url,
      };
    }
    case "PullRequestEvent": {
      const pr = p.pull_request ?? {};
      const merged = p.action === "closed" && !!pr.merged;
      return { ...base, type: "pr", action: merged ? "merged" : base.action, number: pr.number ?? p.number ?? null, isPr: true, title: String(pr.title ?? ""), url: pr.html_url ?? base.url };
    }
    case "PullRequestReviewEvent": {
      const pr = p.pull_request ?? {};
      return { ...base, type: "review", action: String(p.review?.state ?? base.action).toLowerCase(), number: pr.number ?? null, isPr: true, title: String(pr.title ?? ""), body: clip(p.review?.body, BODY_MAX), url: p.review?.html_url ?? pr.html_url ?? base.url };
    }
    case "PullRequestReviewCommentEvent": {
      const pr = p.pull_request ?? {};
      return { ...base, type: "comment", number: pr.number ?? null, isPr: true, title: String(pr.title ?? ""), body: clip(p.comment?.body, BODY_MAX), url: p.comment?.html_url ?? base.url };
    }
    case "IssueCommentEvent": {
      const i = p.issue ?? {};
      return { ...base, type: "comment", number: i.number ?? null, isPr: !!i.pull_request, title: String(i.title ?? ""), body: clip(p.comment?.body, BODY_MAX), url: p.comment?.html_url ?? i.html_url ?? base.url };
    }
    case "IssuesEvent": {
      const i = p.issue ?? {};
      return { ...base, type: "issue", number: i.number ?? null, title: String(i.title ?? ""), url: i.html_url ?? base.url };
    }
    case "ReleaseEvent": {
      const r = p.release ?? {};
      return {
        ...base,
        type: "release",
        title: String(r.name || r.tag_name || ""),
        ref: r.tag_name ?? null,
        body: clip(r.body, BODY_MAX),
        url: r.html_url ?? base.url,
        release: { tag: String(r.tag_name ?? ""), name: String(r.name || r.tag_name || ""), prerelease: !!r.prerelease },
      };
    }
    case "CreateEvent":
      return { ...base, type: "create", action: String(p.ref_type ?? "created"), ref: p.ref ?? null, title: p.ref ? `${p.ref_type} ${p.ref}` : `repository ${repo}` };
    case "DeleteEvent":
      return { ...base, type: "delete", action: String(p.ref_type ?? "deleted"), ref: p.ref ?? null, title: `${p.ref_type ?? ""} ${p.ref ?? ""}`.trim() };
    case "ForkEvent":
      return { ...base, type: "fork", action: "forked", title: String(p.forkee?.full_name ?? repo), url: p.forkee?.html_url ?? base.url };
    case "WatchEvent":
      return { ...base, type: "star", action: "starred", title: repo };
    case "PublicEvent":
      return { ...base, type: "public", action: "made public", title: repo };
    case "MemberEvent":
      return { ...base, type: "member", action: String(p.action ?? "added"), title: String(p.member?.login ?? "") };
    default:
      return { ...base, title: String(e?.type ?? "").replace(/Event$/, "") };
  }
}

/** The caller's recent GitHub activity, newest first. */
export async function myEvents(signal?: AbortSignal) {
  const login = (await ghAuth()).login ?? (await viewerLogin(signal));
  if (!login) return { login: null, items: [] as ActivityItem[] };
  const raw: any[] = [];
  for (let page = 1; page <= PAGES; page++) {
    const batch = await gh<any[]>(`/users/${encodeURIComponent(login)}/events?per_page=100&page=${page}`, { ttlMs: 60_000, signal });
    if (!Array.isArray(batch) || !batch.length) break;
    raw.push(...batch);
    if (batch.length < 100) break;
  }
  return { login, items: raw.map(activityItem).filter((i) => i.repo) };
}
