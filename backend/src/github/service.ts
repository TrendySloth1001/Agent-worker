import { AppError } from "../util/errors.js";
import { gh } from "./client.js";

/** Compact, app-facing shapes of GitHub data (never the raw API dumps). */

const NAME_RE = /^[A-Za-z0-9_.-]{1,100}$/;
const PATCH_MAX = 12_000;
const FILES_MAX = 60;
const BODY_MAX = 1_200;
const TEXT_MAX = 120_000;
const TREE_MAX = 800;

export function checkName(owner: string, repo: string) {
  if (!NAME_RE.test(owner) || !NAME_RE.test(repo)) throw new AppError(400, "bad_request", "Invalid owner/repo");
}

const enc = encodeURIComponent;
const encPath = (p: string) => p.split("/").filter(Boolean).map(enc).join("/");
const clip = (s: string | null | undefined, n: number) => {
  const t = (s ?? "").replace(/\r/g, "").trim();
  return t.length > n ? `${t.slice(0, n).trimEnd()}…` : t;
};
const clampInt = (v: unknown, def: number, min: number, max: number) => {
  const n = Number(v);
  return Number.isFinite(n) ? Math.min(max, Math.max(min, Math.round(n))) : def;
};

export type User = { login: string; avatar: string; url: string } | null;
const user = (u: any): User => (u?.login ? { login: u.login, avatar: u.avatar_url ?? "", url: u.html_url ?? `https://github.com/${u.login}` } : null);
const labels = (ls: any[] | undefined) =>
  (ls ?? []).slice(0, 8).map((l) => ({ name: String(l?.name ?? l ?? ""), color: String(l?.color ?? "") })).filter((l) => l.name);

export function repoSummary(r: any) {
  return {
    fullName: r.full_name as string,
    owner: r.owner?.login as string,
    name: r.name as string,
    avatar: (r.owner?.avatar_url as string) ?? "",
    description: (r.description as string | null) ?? "",
    url: r.html_url as string,
    homepage: (r.homepage as string | null) || null,
    stars: r.stargazers_count ?? 0,
    forks: r.forks_count ?? 0,
    watchers: (r.subscribers_count as number | undefined) ?? null,
    openIssues: r.open_issues_count ?? 0,
    language: (r.language as string | null) ?? null,
    topics: ((r.topics as string[] | undefined) ?? []).slice(0, 12),
    license: (r.license?.spdx_id && r.license.spdx_id !== "NOASSERTION" ? r.license.spdx_id : r.license?.name) ?? null,
    defaultBranch: (r.default_branch as string) ?? "main",
    archived: !!r.archived,
    fork: !!r.fork,
    createdAt: r.created_at ?? null,
    pushedAt: r.pushed_at ?? null,
    updatedAt: r.updated_at ?? null,
  };
}

const commitItem = (c: any) => ({
  sha: c.sha as string,
  shortSha: String(c.sha).slice(0, 7),
  message: String(c.commit?.message ?? "").split("\n")[0].slice(0, 200),
  body: clip(String(c.commit?.message ?? "").split("\n").slice(1).join("\n"), BODY_MAX),
  author: user(c.author),
  authorName: c.commit?.author?.name ?? c.author?.login ?? "",
  date: c.commit?.author?.date ?? c.commit?.committer?.date ?? null,
  url: c.html_url as string,
  parents: (c.parents ?? []).length,
});

const fileItem = (f: any) => {
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
};
const files = (fs: any[] | undefined) => ({
  files: (fs ?? []).slice(0, FILES_MAX).map(fileItem),
  filesTruncated: (fs ?? []).length > FILES_MAX,
});

// ---- search --------------------------------------------------------------

export async function searchRepos(q: string, sort?: string, perPage?: unknown, signal?: AbortSignal) {
  const s = sort && ["stars", "forks", "updated", "help-wanted-issues"].includes(sort) ? `&sort=${sort}&order=desc` : "";
  const n = clampInt(perPage, 10, 1, 30);
  const d = await gh(`/search/repositories?q=${enc(q)}${s}&per_page=${n}`, { signal });
  return { total: d.total_count ?? 0, incomplete: !!d.incomplete_results, items: (d.items ?? []).map(repoSummary) };
}

export async function searchCode(q: string, perPage?: unknown) {
  const n = clampInt(perPage, 10, 1, 30);
  const d = await gh(`/search/code?q=${enc(q)}&per_page=${n}`, { accept: "application/vnd.github.text-match+json" });
  return {
    total: d.total_count ?? 0,
    incomplete: !!d.incomplete_results,
    items: (d.items ?? []).map((i: any) => ({
      name: i.name,
      path: i.path,
      repo: i.repository?.full_name ?? "",
      avatar: i.repository?.owner?.avatar_url ?? "",
      url: i.html_url,
      sha: i.sha,
      fragments: (i.text_matches ?? []).slice(0, 2).map((m: any) => clip(m.fragment, 400)),
    })),
  };
}

export async function searchIssues(q: string, perPage?: unknown) {
  const n = clampInt(perPage, 10, 1, 30);
  const d = await gh(`/search/issues?q=${enc(q)}&per_page=${n}`);
  return {
    total: d.total_count ?? 0,
    incomplete: !!d.incomplete_results,
    items: (d.items ?? []).map((i: any) => ({
      ...issueItem(i),
      repo: String(i.repository_url ?? "").replace("https://api.github.com/repos/", ""),
    })),
  };
}

export async function searchCommits(q: string, perPage?: unknown) {
  const n = clampInt(perPage, 10, 1, 30);
  const d = await gh(`/search/commits?q=${enc(q)}&per_page=${n}`);
  return {
    total: d.total_count ?? 0,
    incomplete: !!d.incomplete_results,
    items: (d.items ?? []).map((c: any) => ({ ...commitItem(c), repo: c.repository?.full_name ?? "" })),
  };
}

// ---- repository ---------------------------------------------------------

export async function repoRaw(owner: string, repo: string, signal?: AbortSignal) {
  checkName(owner, repo);
  return gh(`/repos/${owner}/${repo}`, { signal });
}

export async function repoDetail(owner: string, repo: string, signal?: AbortSignal) {
  const r = await repoRaw(owner, repo, signal);
  const base = `/repos/${r.full_name}`;
  const [langs, release, readme] = await Promise.all([
    gh<Record<string, number>>(`${base}/languages`, { signal }).catch(() => ({})),
    gh(`${base}/releases/latest`, { allow404: true, signal }).catch(() => null),
    gh<string>(`${base}/readme`, { accept: "application/vnd.github.raw+json", text: true, allow404: true, signal }).catch(() => null),
  ]);
  const total = Object.values(langs).reduce((a, b) => a + b, 0) || 1;
  return {
    ...repoSummary(r),
    languages: Object.entries(langs)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 8)
      .map(([name, bytes]) => ({ name, bytes, pct: Math.round((bytes / total) * 1000) / 10 })),
    latestRelease: release
      ? { tag: release.tag_name, name: release.name || release.tag_name, publishedAt: release.published_at, url: release.html_url }
      : null,
    readme: readme ? readmeExcerpt(readme) : "",
  };
}

/** First prose of a README: badges, HTML and images stripped. */
function readmeExcerpt(md: string): string {
  const text = md
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/!\[[^\]]*\]\([^)]*\)/g, "")
    .replace(/\[!\[[^\]]*\]\([^)]*\)\]\([^)]*\)/g, "")
    .split("\n")
    .map((l) => l.trimEnd())
    .filter((l) => l.trim() && !/^\s*\[!\[/.test(l))
    .join("\n");
  return clip(text, 1_500);
}

export async function commits(owner: string, repo: string, q: { sha?: string; path?: string; perPage?: unknown; stats?: boolean }, signal?: AbortSignal) {
  checkName(owner, repo);
  const n = clampInt(q.perPage, 15, 1, 50);
  const params = new URLSearchParams({ per_page: String(n) });
  if (q.sha) params.set("sha", q.sha);
  if (q.path) params.set("path", q.path);
  const list = await gh<any[]>(`/repos/${owner}/${repo}/commits?${params}`, { signal });
  const items = list.map(commitItem);
  if (q.stats !== false) {
    // The list has no line counts; fetch them for the first few (cached).
    const firstN = items.slice(0, 15);
    const stats = await Promise.all(
      firstN.map((c) => gh(`/repos/${owner}/${repo}/commits/${c.sha}`, { signal }).then((d) => d.stats).catch(() => null)),
    );
    return items.map((c, i) => ({ ...c, additions: stats[i]?.additions ?? null, deletions: stats[i]?.deletions ?? null }));
  }
  return items.map((c) => ({ ...c, additions: null, deletions: null }));
}

export async function commit(owner: string, repo: string, sha: string) {
  checkName(owner, repo);
  const c = await gh(`/repos/${owner}/${repo}/commits/${enc(sha)}`);
  return {
    ...commitItem(c),
    fullMessage: clip(c.commit?.message, 4_000),
    committer: user(c.committer),
    parentShas: (c.parents ?? []).map((p: any) => p.sha),
    stats: { additions: c.stats?.additions ?? 0, deletions: c.stats?.deletions ?? 0, total: c.stats?.total ?? 0 },
    ...files(c.files),
  };
}

export async function compare(owner: string, repo: string, base: string, head: string) {
  checkName(owner, repo);
  const d = await gh(`/repos/${owner}/${repo}/compare/${enc(base)}...${enc(head)}`);
  const fs = d.files ?? [];
  return {
    base,
    head,
    status: d.status,
    aheadBy: d.ahead_by ?? 0,
    behindBy: d.behind_by ?? 0,
    totalCommits: d.total_commits ?? 0,
    url: d.html_url,
    stats: {
      additions: fs.reduce((n: number, f: any) => n + (f.additions ?? 0), 0),
      deletions: fs.reduce((n: number, f: any) => n + (f.deletions ?? 0), 0),
      changedFiles: fs.length,
    },
    commits: (d.commits ?? []).slice(-50).reverse().map(commitItem),
    ...files(fs),
  };
}

type Entry = { name: string; path: string; type: "dir" | "file" | "symlink" | "submodule"; size: number };
const sortEntries = (a: Entry, b: Entry) => (a.type === "dir") === (b.type === "dir") ? a.path.localeCompare(b.path) : a.type === "dir" ? -1 : 1;

export async function tree(owner: string, repo: string, ref: string, path = "", recursive = false) {
  checkName(owner, repo);
  const clean = path.replace(/^\/+|\/+$/g, "");
  if (recursive) {
    const d = await gh(`/repos/${owner}/${repo}/git/trees/${enc(ref)}?recursive=1`);
    const prefix = clean ? `${clean}/` : "";
    const all: Entry[] = (d.tree ?? [])
      .filter((e: any) => !prefix || String(e.path).startsWith(prefix))
      .map((e: any) => ({
        name: String(e.path).split("/").pop()!,
        path: e.path,
        type: e.type === "tree" ? "dir" : e.type === "commit" ? "submodule" : "file",
        size: e.size ?? 0,
      }));
    all.sort(sortEntries);
    return { ref, path: clean, recursive: true, truncated: !!d.truncated || all.length > TREE_MAX, entries: all.slice(0, TREE_MAX) };
  }
  const d = await gh(`/repos/${owner}/${repo}/contents/${encPath(clean)}?ref=${enc(ref)}`);
  if (!Array.isArray(d)) throw new AppError(400, "bad_request", "That path is a file; use /contents");
  const entries: Entry[] = d.map((e: any) => ({ name: e.name, path: e.path, type: e.type, size: e.size ?? 0 }));
  entries.sort(sortEntries);
  return { ref, path: clean, recursive: false, truncated: entries.length > TREE_MAX, entries: entries.slice(0, TREE_MAX) };
}

export async function contents(owner: string, repo: string, ref: string, path: string) {
  checkName(owner, repo);
  const clean = path.replace(/^\/+|\/+$/g, "");
  if (!clean) throw new AppError(400, "bad_request", "path is required");
  const d = await gh(`/repos/${owner}/${repo}/contents/${encPath(clean)}?ref=${enc(ref)}`);
  if (Array.isArray(d)) throw new AppError(400, "bad_request", "That path is a directory; use /tree");
  let text = "";
  let binary = false;
  if (d.encoding === "base64" && d.content) {
    const buf = Buffer.from(d.content, "base64");
    binary = buf.subarray(0, 8000).includes(0);
    if (!binary) text = buf.toString("utf8");
  } else if ((d.size ?? 0) > 0) {
    // Over 1 MB the contents API sends no body.
    binary = false;
    text = "";
  }
  return {
    ref,
    path: d.path,
    name: d.name,
    size: d.size ?? 0,
    url: d.html_url,
    language: languageOf(d.name),
    binary,
    tooLarge: !binary && !text && (d.size ?? 0) > 0,
    truncated: text.length > TEXT_MAX,
    text: text.slice(0, TEXT_MAX),
  };
}

const EXT_LANG: Record<string, string> = {
  ts: "typescript", tsx: "typescript", js: "javascript", jsx: "javascript", mjs: "javascript", cjs: "javascript",
  py: "python", go: "go", rs: "rust", java: "java", kt: "kotlin", swift: "swift", dart: "dart", rb: "ruby",
  php: "php", c: "c", h: "c", cc: "cpp", cpp: "cpp", hpp: "cpp", cs: "cs", sh: "bash", bash: "bash", zsh: "bash",
  sql: "sql", yaml: "yaml", yml: "yaml", toml: "ini", json: "json", md: "markdown", mdx: "markdown", html: "xml",
  xml: "xml", css: "css", scss: "scss", lua: "lua", r: "r", scala: "scala", ex: "elixir", exs: "elixir",
  hs: "haskell", vue: "xml", svelte: "xml", gradle: "gradle", dockerfile: "dockerfile", makefile: "makefile",
};
function languageOf(name: string): string {
  const lower = name.toLowerCase();
  if (lower === "dockerfile" || lower === "makefile") return lower;
  return EXT_LANG[lower.split(".").pop() ?? ""] ?? "";
}

export async function branches(owner: string, repo: string) {
  const r = await repoRaw(owner, repo);
  const list = await gh<any[]>(`/repos/${owner}/${repo}/branches?per_page=100`);
  // The default branch may sit beyond the first page: always list it.
  if (!list.some((b) => b.name === r.default_branch)) {
    const d = await gh(`/repos/${owner}/${repo}/branches/${enc(r.default_branch)}`, { allow404: true }).catch(() => null);
    list.unshift(d ?? { name: r.default_branch });
  }
  return {
    defaultBranch: r.default_branch,
    items: list
      .map((b) => ({ name: b.name as string, sha: b.commit?.sha ?? "", protected: !!b.protected, default: b.name === r.default_branch }))
      .sort((a, b) => Number(b.default) - Number(a.default)),
  };
}

function issueItem(i: any) {
  const isPr = !!i.pull_request;
  const merged = !!(i.merged_at ?? i.pull_request?.merged_at);
  return {
    number: i.number as number,
    title: i.title as string,
    state: (merged ? "merged" : i.draft && i.state === "open" ? "draft" : i.state) as string,
    stateReason: i.state_reason ?? null,
    isPr,
    user: user(i.user),
    labels: labels(i.labels),
    comments: i.comments ?? null,
    createdAt: i.created_at ?? null,
    updatedAt: i.updated_at ?? null,
    closedAt: i.closed_at ?? null,
    url: i.html_url as string,
    body: clip(i.body, BODY_MAX),
  };
}

const STATES = new Set(["open", "closed", "all"]);
const stateOf = (s: unknown) => (typeof s === "string" && STATES.has(s) ? s : "open");

export async function pulls(owner: string, repo: string, state?: unknown, perPage?: unknown) {
  checkName(owner, repo);
  const n = clampInt(perPage, 15, 1, 50);
  const list = await gh<any[]>(`/repos/${owner}/${repo}/pulls?state=${stateOf(state)}&per_page=${n}&sort=updated&direction=desc`);
  return {
    state: stateOf(state),
    items: list.map((p) => ({ ...issueItem({ ...p, pull_request: {} }), head: p.head?.ref ?? "", base: p.base?.ref ?? "" })),
  };
}

export async function pull(owner: string, repo: string, n: number) {
  checkName(owner, repo);
  if (!Number.isInteger(n) || n <= 0) throw new AppError(400, "bad_request", "Invalid pull number");
  const [p, fs] = await Promise.all([
    gh(`/repos/${owner}/${repo}/pulls/${n}`),
    gh<any[]>(`/repos/${owner}/${repo}/pulls/${n}/files?per_page=100`),
  ]);
  return {
    ...issueItem({ ...p, pull_request: {} }),
    body: clip(p.body, 4_000),
    head: p.head?.ref ?? "",
    base: p.base?.ref ?? "",
    commits: p.commits ?? 0,
    additions: p.additions ?? 0,
    deletions: p.deletions ?? 0,
    changedFiles: p.changed_files ?? 0,
    mergeable: p.mergeable ?? null,
    mergedBy: user(p.merged_by),
    ...files(fs),
  };
}

export async function issues(owner: string, repo: string, state?: unknown, perPage?: unknown) {
  checkName(owner, repo);
  const n = clampInt(perPage, 15, 1, 50);
  // The issues API also lists pull requests; over-fetch and drop them.
  const list = await gh<any[]>(`/repos/${owner}/${repo}/issues?state=${stateOf(state)}&per_page=100&sort=updated&direction=desc`);
  return { state: stateOf(state), items: list.filter((i) => !i.pull_request).slice(0, n).map(issueItem) };
}

export async function contributors(owner: string, repo: string, perPage?: unknown) {
  checkName(owner, repo);
  const n = clampInt(perPage, 20, 1, 50);
  const list = (await gh<any[] | null>(`/repos/${owner}/${repo}/contributors?per_page=${n}`, { allow404: true })) ?? [];
  // 204 (empty repo) parses as an empty body; guard against non-arrays.
  return { items: (Array.isArray(list) ? list : []).map((c) => ({ login: c.login, avatar: c.avatar_url, contributions: c.contributions, url: c.html_url })) };
}

export async function releases(owner: string, repo: string, perPage?: unknown) {
  checkName(owner, repo);
  const n = clampInt(perPage, 10, 1, 30);
  const list = await gh<any[]>(`/repos/${owner}/${repo}/releases?per_page=${n}`);
  return {
    items: list.map((r) => ({
      tag: r.tag_name,
      name: r.name || r.tag_name,
      publishedAt: r.published_at,
      prerelease: !!r.prerelease,
      draft: !!r.draft,
      url: r.html_url,
      author: user(r.author),
      assets: (r.assets ?? []).length,
      body: clip(r.body, BODY_MAX),
    })),
  };
}
