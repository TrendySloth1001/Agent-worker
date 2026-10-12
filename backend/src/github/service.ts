import { AppError } from "../util/errors.js";
import { redactForExternal } from "../nlp/pii.js";
import { gh, ghAuth, ghGraphql, lastRate, tokenScopes } from "./client.js";
import { publicAttempts, queryTokens, rankNames, rankRepos, repairTypos, scoreRepo } from "./repoSearch.js";

/** Compact, app-facing shapes of GitHub data (never the raw API dumps). */

/** On the shared server token, non-owners search public repositories only. */
const publicQ = async (raw: string) => {
  const q = redactForExternal(raw); // search text leaves the app: no PII
  return (await ghAuth()).publicOnly ? `${q} is:public` : q;
};
const publicOnly = async () => (await ghAuth()).publicOnly;

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
    private: !!r.private,
    visibility: (r.visibility as string | undefined) ?? (r.private ? "private" : "public"),
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

const REPO_SORTS = new Set(["stars", "forks", "updated", "help-wanted-issues"]);

/**
 * Repository search that survives loose text: the query gets qualifiers
 * (in:name,description,readme, language:, user:, topic:), then falls back to
 * plain words and a typo-repaired variant when results are thin; everything
 * found is merged, de-duplicated and re-ranked ("best-match"), or sorted by
 * stars / last update.
 */
export async function searchRepos(q: string, sort?: string, perPage?: unknown, signal?: AbortSignal) {
  const n = clampInt(perPage, 10, 1, 30);
  const mode = sort === "stars" || sort === "updated" || sort === "forks" ? sort : "best-match";
  // Raw GitHub syntax (qualifiers, OR, quotes) beyond simple words: run as typed first.
  const s = mode !== "best-match" && REPO_SORTS.has(mode) ? `&sort=${mode}&order=desc` : "";
  const run = async (query: string) => {
    const d = await gh(`/search/repositories?q=${enc(await publicQ(query))}${s}&per_page=${Math.max(n, 20)}`, { signal });
    return { total: (d.total_count as number) ?? 0, incomplete: !!d.incomplete_results, items: ((d.items ?? []) as any[]).map(repoSummary) };
  };
  const attempts = publicAttempts(q);
  const fixed = repairTypos(q.replace(/\b[a-z-]+:\S+/gi, " ").trim());
  const seen = new Map<string, { r: ReturnType<typeof repoSummary>; rank: number }>();
  let total = 0;
  let incomplete = false;
  let used = attempts[0] ?? q;
  let tries = 0;
  let ranFixed = false;
  for (const a of attempts) {
    if (tries >= 4) break;
    const isFixed = !!fixed && a.includes(fixed);
    // Enough hits already: stop spending search quota (but try a typo repair once).
    if (seen.size >= n && tries >= 1 && (!isFixed || ranFixed)) continue;
    ranFixed ||= isFixed;
    tries++;
    let res;
    try {
      res = await run(a);
    } catch (e) {
      if (tries === 1 && !attempts[1]) throw e;
      if ((e as AppError).status === 429) break;
      continue;
    }
    if (!total && res.total) used = a;
    total = Math.max(total, res.total);
    incomplete ||= res.incomplete;
    res.items.forEach((r, i) => {
      const key = r.fullName.toLowerCase();
      const rank = 1 - i / Math.max(res.items.length, 1);
      const prev = seen.get(key);
      if (!prev || prev.rank < rank) seen.set(key, { r, rank });
    });
  }
  // Ranking text: the repaired words when the typed ones found little.
  const rankText = fixed ?? q.replace(/\b[a-z-]+:\S+/gi, " ");
  const scored = [...seen.values()].map(({ r, rank }) => {
    const m = scoreRepo(rankText, r);
    const pop = Math.min(1, Math.log10((r.stars ?? 0) + 1) / 5);
    return { r, score: m.score * 0.6 + rank * 0.3 + pop * 0.25, matched: m.matched };
  });
  if (mode === "stars") scored.sort((a, b) => b.r.stars - a.r.stars);
  else if (mode === "updated") scored.sort((a, b) => Date.parse(b.r.pushedAt ?? "") - Date.parse(a.r.pushedAt ?? "") || 0);
  else if (mode === "forks") scored.sort((a, b) => b.r.forks - a.r.forks);
  else scored.sort((a, b) => b.score - a.score);
  return {
    total: Math.max(total, scored.length),
    incomplete,
    sort: mode,
    query: used,
    corrected: fixed,
    tokens: queryTokens(rankText),
    items: scored.slice(0, n).map((x) => ({ ...x.r, score: Math.round(x.score * 1000) / 1000, matched: x.matched })),
  };
}

export async function searchCode(q: string, perPage?: unknown) {
  const n = clampInt(perPage, 10, 1, 30);
  const d = await gh(`/search/code?q=${enc(redactForExternal(q))}&per_page=${n}`, { accept: "application/vnd.github.text-match+json" });
  if (await publicOnly()) d.items = (d.items ?? []).filter((i: any) => i.repository?.private === false);
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
  const d = await gh(`/search/issues?q=${enc(await publicQ(q))}&per_page=${n}`);
  return {
    total: d.total_count ?? 0,
    incomplete: !!d.incomplete_results,
    items: (d.items ?? []).map((i: any) => ({
      ...issueItem(i),
      repo: String(i.repository_url ?? "").replace("https://api.github.com/repos/", ""),
    })),
  };
}

const COMMIT_SORTS = new Set(["author-date", "committer-date"]);

export async function searchCommits(q: string, perPage?: unknown, sort?: string) {
  const n = clampInt(perPage, 10, 1, 30);
  const order = sort && COMMIT_SORTS.has(sort) ? `&sort=${sort}&order=desc` : "";
  const d = await gh(`/search/commits?q=${enc(redactForExternal(q))}${order}&per_page=${n}`);
  if (await publicOnly()) d.items = (d.items ?? []).filter((c: any) => c.repository?.private === false);
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

export type CommitsQuery = {
  sha?: string;
  path?: string;
  author?: string;
  since?: string;
  until?: string;
  /** Message / author / sha filter (GitHub commit search on the default branch). */
  q?: string;
  after?: string;
  perPage?: unknown;
  stats?: boolean;
};

const GQL_COMMIT = `oid messageHeadline messageBody authoredDate committedDate url additions deletions parents { totalCount } author { name email user { login avatarUrl url } }`;
const fromGqlCommit = (c: any) => ({
  sha: c.oid as string,
  shortSha: String(c.oid).slice(0, 7),
  message: String(c.messageHeadline ?? "").slice(0, 200),
  body: clip(c.messageBody, BODY_MAX),
  author: c.author?.user ? { login: c.author.user.login, avatar: c.author.user.avatarUrl ?? "", url: c.author.user.url ?? "" } : null,
  authorName: c.author?.name ?? c.author?.user?.login ?? "",
  date: c.authoredDate ?? c.committedDate ?? null,
  url: c.url as string,
  parents: c.parents?.totalCount ?? 0,
  additions: (c.additions as number | undefined) ?? null,
  deletions: (c.deletions as number | undefined) ?? null,
});
type CommitRow = ReturnType<typeof fromGqlCommit>;
export type CommitPage = { items: CommitRow[]; totalCount: number | null; nextCursor: string | null };

const isoOrUndef = (v?: string) => {
  if (!v) return undefined;
  const t = Date.parse(v);
  if (!Number.isFinite(t)) throw new AppError(400, "bad_request", "Invalid date");
  return new Date(t).toISOString();
};

/**
 * One page of commit history, newest first. Cursors: `g:<graphql cursor>`,
 * `r:<rest page>` or `s:<search page>`; nextCursor null at the end.
 */
export async function commitsPage(owner: string, repo: string, q: CommitsQuery, signal?: AbortSignal): Promise<CommitPage> {
  checkName(owner, repo);
  const n = clampInt(q.perPage, 15, 1, 100);
  const after = q.after ?? "";
  const filter = (q.q ?? "").trim().slice(0, 200);
  if (filter) return commitSearch(owner, repo, filter, after, n, signal);
  const since = isoOrUndef(q.since);
  const until = isoOrUndef(q.until);
  const auth = await ghAuth();
  if (auth.token && !after.startsWith("r:")) {
    try {
      let author: Record<string, unknown> | undefined;
      if (q.author) {
        if (q.author.includes("@")) author = { emails: [q.author] };
        else {
          const u = await ghGraphql<{ user: { id: string } | null }>(`query($l: String!) { user(login: $l) { id } }`, { l: q.author }, { signal, partial: true });
          if (!u?.user?.id) return { items: [], totalCount: 0, nextCursor: null };
          author = { id: u.user.id };
        }
      }
      const d = await ghGraphql<{ repository: any }>(
        `query($owner: String!, $name: String!, $expr: String!, $n: Int!, $after: String, $path: String, $since: GitTimestamp, $until: GitTimestamp, $author: CommitAuthor) {
          repository(owner: $owner, name: $name) { object(expression: $expr) { ... on Commit {
            history(first: $n, after: $after, path: $path, since: $since, until: $until, author: $author) {
              totalCount pageInfo { hasNextPage endCursor } nodes { ${GQL_COMMIT} }
            } } } }
        }`,
        {
          owner,
          name: repo,
          expr: q.sha || "HEAD",
          n,
          after: after.startsWith("g:") ? after.slice(2) : null,
          path: q.path || null,
          since: since ?? null,
          until: until ?? null,
          author: author ?? null,
        },
        { signal },
      );
      if (!d?.repository) throw new AppError(404, "not_found", "GitHub: not found (or private)");
      const h = d.repository.object?.history;
      if (!h) throw new AppError(404, "not_found", "GitHub: no such branch or commit");
      return {
        items: (h.nodes ?? []).map(fromGqlCommit),
        totalCount: typeof h.totalCount === "number" ? h.totalCount : null,
        nextCursor: h.pageInfo?.hasNextPage && h.pageInfo.endCursor ? `g:${h.pageInfo.endCursor}` : null,
      };
    } catch (e) {
      const status = (e as AppError).status;
      if (status === 404 || status === 409 || status === 429 || status === 400 || signal?.aborted) throw e;
      // Fall through to REST.
    }
  }
  const pageNo = after.startsWith("r:") ? clampInt(after.slice(2), 1, 1, 100_000) : 1;
  const params = new URLSearchParams({ per_page: String(n), page: String(pageNo) });
  if (q.sha) params.set("sha", q.sha);
  if (q.path) params.set("path", q.path);
  if (q.author) params.set("author", q.author);
  if (since) params.set("since", since);
  if (until) params.set("until", until);
  const list = await gh<any[]>(`/repos/${owner}/${repo}/commits?${params}`, { signal });
  let items = list.map((c) => ({ ...commitItem(c), additions: null as number | null, deletions: null as number | null }));
  if (q.stats !== false) {
    const stats = await Promise.all(
      items.slice(0, 15).map((c) => gh(`/repos/${owner}/${repo}/commits/${c.sha}`, { signal }).then((d) => d.stats).catch(() => null)),
    );
    items = items.map((c, i) => ({ ...c, additions: stats[i]?.additions ?? null, deletions: stats[i]?.deletions ?? null }));
  }
  return { items, totalCount: null, nextCursor: list.length === n ? `r:${pageNo + 1}` : null };
}

/** Commits matching a message / author / sha filter. */
async function commitSearch(owner: string, repo: string, filter: string, after: string, n: number, signal?: AbortSignal): Promise<CommitPage> {
  if (/^[0-9a-f]{7,40}$/i.test(filter) && !after) {
    const c = await gh(`/repos/${owner}/${repo}/commits/${enc(filter)}`, { allow404: true, signal }).catch(() => null);
    if (c?.sha) return { items: [{ ...commitItem(c), additions: c.stats?.additions ?? null, deletions: c.stats?.deletions ?? null }], totalCount: 1, nextCursor: null };
  }
  const pageNo = after.startsWith("s:") ? clampInt(after.slice(2), 1, 1, 10) : 1;
  // Search returns at most 1,000 results (10 pages of 100).
  const per = Math.min(n, 100);
  const words = filter.replace(/\b(repo|org|user):\S+/gi, " ").trim();
  const d = await gh(`/search/commits?q=${enc(`repo:${owner}/${repo} ${redactForExternal(words)}`)}&sort=committer-date&order=desc&per_page=${per}&page=${pageNo}`, { signal });
  const items = ((d.items ?? []) as any[]).map((c) => ({ ...commitItem(c), additions: null as number | null, deletions: null as number | null }));
  const total = (d.total_count as number) ?? items.length;
  return { items, totalCount: total, nextCursor: items.length === per && pageNo * per < Math.min(total, 1000) ? `s:${pageNo + 1}` : null };
}

/** The first page of commits as a plain list (grounding, older callers). */
export async function commits(owner: string, repo: string, q: { sha?: string; path?: string; perPage?: unknown; stats?: boolean }, signal?: AbortSignal) {
  return (await commitsPage(owner, repo, q, signal)).items;
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

export type BranchItem = { name: string; sha: string; date: string | null; protected: boolean; default: boolean };
const BRANCH_PAGES_MAX = 50;
const BRANCH_CONCURRENCY = 6;
const branchCache = new Map<string, { at: number; value: { defaultBranch: string; items: BranchItem[]; complete: boolean } }>();
const BRANCH_TTL = 5 * 60_000;

const REFS_QUERY = `query($owner: String!, $name: String!, $after: String) {
  repository(owner: $owner, name: $name) {
    defaultBranchRef { name }
    refs(refPrefix: "refs/heads/", first: 100, after: $after) {
      totalCount pageInfo { hasNextPage endCursor }
      nodes { name target { oid ... on Commit { committedDate } } }
    }
  }
}`;

/** Every branch with its head commit date (GraphQL; pages fetched in parallel when cursors are offsets). */
async function allBranchesGql(owner: string, repo: string, signal?: AbortSignal) {
  const first = await ghGraphql<{ repository: any }>(REFS_QUERY, { owner, name: repo, after: null }, { signal });
  const r = first?.repository;
  if (!r) throw new AppError(404, "not_found", "GitHub: not found (or private)");
  const def: string = r.defaultBranchRef?.name ?? "";
  const total: number = r.refs?.totalCount ?? 0;
  const pages: any[][] = [r.refs?.nodes ?? []];
  const pagesNeeded = Math.min(BRANCH_PAGES_MAX, Math.ceil(total / 100));
  // Ref cursors are base64 offsets ("MTAw" = "100"): fetch the rest side by side.
  if (r.refs?.pageInfo?.hasNextPage && Buffer.from(String(r.refs.pageInfo.endCursor), "base64").toString() === "100") {
    const offsets = Array.from({ length: pagesNeeded - 1 }, (_, i) => (i + 1) * 100);
    for (let i = 0; i < offsets.length; i += BRANCH_CONCURRENCY) {
      const batch = await Promise.all(
        offsets.slice(i, i + BRANCH_CONCURRENCY).map((off) =>
          ghGraphql<{ repository: any }>(REFS_QUERY, { owner, name: repo, after: Buffer.from(String(off)).toString("base64") }, { signal }).then(
            (d) => d?.repository?.refs?.nodes ?? [],
          ),
        ),
      );
      pages.push(...batch);
    }
  } else {
    let page = r.refs?.pageInfo;
    while (page?.hasNextPage && pages.length < BRANCH_PAGES_MAX) {
      const d = await ghGraphql<{ repository: any }>(REFS_QUERY, { owner, name: repo, after: page.endCursor }, { signal });
      pages.push(d?.repository?.refs?.nodes ?? []);
      page = d?.repository?.refs?.pageInfo;
    }
  }
  const seen = new Set<string>();
  const items: BranchItem[] = [];
  for (const x of pages.flat()) {
    if (!x?.name || seen.has(x.name)) continue;
    seen.add(x.name);
    items.push({ name: x.name, sha: x.target?.oid ?? "", date: x.target?.committedDate ?? null, protected: false, default: x.name === def });
  }
  return { defaultBranch: def, items, complete: items.length >= total };
}

/** REST fallback: every page of /branches (no dates). */
async function allBranchesRest(owner: string, repo: string, signal?: AbortSignal) {
  const r = await repoRaw(owner, repo, signal);
  const items: BranchItem[] = [];
  let complete = false;
  for (let page = 1; page <= BRANCH_PAGES_MAX; page++) {
    const list = await gh<any[]>(`/repos/${owner}/${repo}/branches?per_page=100&page=${page}`, { signal });
    for (const b of list) items.push({ name: b.name, sha: b.commit?.sha ?? "", date: null, protected: !!b.protected, default: b.name === r.default_branch });
    if (list.length < 100) {
      complete = true;
      break;
    }
  }
  return { defaultBranch: r.default_branch as string, items, complete };
}

/**
 * All branches of a repository (cached 5 minutes): default first, then by last
 * commit date; [q] filters by fuzzy name match. Paged by offset cursors.
 */
export async function branches(owner: string, repo: string, opts: { q?: string; after?: string; limit?: unknown; refresh?: boolean } = {}, signal?: AbortSignal) {
  checkName(owner, repo);
  const auth = await ghAuth();
  const key = `${auth.key}|${owner.toLowerCase()}/${repo.toLowerCase()}`;
  let hit = branchCache.get(key);
  if (!hit || opts.refresh || Date.now() - hit.at > BRANCH_TTL) {
    let value;
    try {
      value = auth.token ? await allBranchesGql(owner, repo, signal) : await allBranchesRest(owner, repo, signal);
    } catch (e) {
      const status = (e as AppError).status;
      if (!auth.token || status === 404 || status === 409 || status === 429 || signal?.aborted) throw e;
      value = await allBranchesRest(owner, repo, signal);
    }
    hit = { at: Date.now(), value };
    branchCache.set(key, hit);
    while (branchCache.size > 100) branchCache.delete(branchCache.keys().next().value!);
  }
  const { defaultBranch, items: all, complete } = hit.value;
  const time = (b: BranchItem) => (b.date ? Date.parse(b.date) : 0);
  const q = (opts.q ?? "").trim();
  const sorted = q
    ? rankNames(q, all, (b) => b.name).map((x) => x.item)
    : [...all].sort((a, b) => Number(b.default) - Number(a.default) || time(b) - time(a) || a.name.localeCompare(b.name));
  const limit = clampInt(opts.limit, 100, 1, 500);
  const offset = clampInt(opts.after, 0, 0, 1_000_000);
  const items = sorted.slice(offset, offset + limit);
  return {
    defaultBranch,
    totalCount: all.length,
    matchCount: sorted.length,
    complete,
    items,
    nextCursor: offset + limit < sorted.length ? String(offset + limit) : null,
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

// ---- the token's own account --------------------------------------------

/** Who the token belongs to, its scopes, private repo count and quota. */
export async function me(signal?: AbortSignal) {
  const u = await gh(`/user`, { ttlMs: 60_000, signal });
  const auth = await ghAuth();
  const scopes = await tokenScopes();
  // Fine-grained tokens omit the private counters: count what the token can list.
  let privateRepos: number | null = (u.total_private_repos as number | undefined) ?? null;
  if (privateRepos == null) {
    const list = await gh<any[]>(`/user/repos?visibility=private&per_page=100`, { ttlMs: 60_000, signal }).catch(() => null);
    privateRepos = Array.isArray(list) ? list.length : null;
  }
  return {
    login: u.login as string,
    name: (u.name as string | null) ?? null,
    avatar: (u.avatar_url as string) ?? "",
    url: (u.html_url as string) ?? `https://github.com/${u.login}`,
    publicRepos: u.public_repos ?? 0,
    // Only present when the token may see private data.
    privateRepos,
    ownedPrivateRepos: (u.owned_private_repos as number | undefined) ?? null,
    scopes,
    // Fine-grained tokens send no X-OAuth-Scopes header.
    tokenKind: scopes == null ? "fine-grained" : "classic",
    canReadPrivate: scopes == null ? (privateRepos ?? 0) > 0 : scopes.includes("repo"),
    rate: await lastRate("core"),
    /** "user": the caller's own connected account; "server": the server token (owner). */
    source: auth.kind,
  };
}

const VISIBILITY = new Set(["all", "public", "private"]);
const MY_SORTS = new Set(["updated", "pushed", "created", "full_name"]);
const MY_PAGES_MAX = 50;
const MY_TTL = 5 * 60_000;
const myCache = new Map<string, { at: number; value: ReturnType<typeof repoSummary>[] }>();

/**
 * Every repository the token's user can access (owned, collaborator,
 * organization member), all pages, cached per user for 5 minutes.
 */
export async function allMyRepos(opts: { refresh?: boolean } = {}, signal?: AbortSignal) {
  const auth = await ghAuth();
  const hit = myCache.get(auth.key);
  if (hit && !opts.refresh && Date.now() - hit.at < MY_TTL) return hit.value;
  const out: ReturnType<typeof repoSummary>[] = [];
  for (let page = 1; page <= MY_PAGES_MAX; page++) {
    const params = new URLSearchParams({
      visibility: "all",
      sort: "pushed",
      direction: "desc",
      per_page: "100",
      page: String(page),
      affiliation: "owner,collaborator,organization_member",
    });
    const list = await gh<any[]>(`/user/repos?${params}`, { ttlMs: opts.refresh ? 0 : 60_000, signal });
    out.push(...list.map(repoSummary));
    if (list.length < 100) break;
  }
  const value = auth.publicOnly ? out.filter((r) => !r.private) : out;
  myCache.set(auth.key, { at: Date.now(), value });
  while (myCache.size > 200) myCache.delete(myCache.keys().next().value!);
  return value;
}

const sorters: Record<string, (a: ReturnType<typeof repoSummary>, b: ReturnType<typeof repoSummary>) => number> = {
  updated: (a, b) => Date.parse(b.updatedAt ?? "") - Date.parse(a.updatedAt ?? "") || 0,
  pushed: (a, b) => Date.parse(b.pushedAt ?? "") - Date.parse(a.pushedAt ?? "") || 0,
  created: (a, b) => Date.parse(b.createdAt ?? "") - Date.parse(a.createdAt ?? "") || 0,
  full_name: (a, b) => a.fullName.localeCompare(b.fullName),
};

/** Repositories the token's user can access; [perPage] caps the list (0 / absent = all). */
export async function myRepos(q: { visibility?: unknown; sort?: unknown; perPage?: unknown; refresh?: boolean } = {}, signal?: AbortSignal) {
  const visibility = typeof q.visibility === "string" && VISIBILITY.has(q.visibility) ? q.visibility : "all";
  const sort = typeof q.sort === "string" && MY_SORTS.has(q.sort) ? q.sort : "updated";
  const all = await allMyRepos({ refresh: q.refresh }, signal);
  const list = all.filter((r) => visibility === "all" || (visibility === "private" ? r.private : !r.private)).sort(sorters[sort]);
  const cap = q.perPage == null || q.perPage === "" ? list.length : clampInt(q.perPage, list.length, 1, 10_000);
  return { visibility, sort, total: list.length, items: list.slice(0, cap) };
}

/** The user's repositories ranked for loose text ("keepit", "reprot card"). */
export async function searchMyRepos(text: string, limit?: unknown, signal?: AbortSignal) {
  const all = await allMyRepos({}, signal);
  const res = rankRepos(text, all, { limit: clampInt(limit, 20, 1, 100) });
  return {
    q: text,
    tokens: queryTokens(text),
    confident: res.confident,
    total: all.length,
    items: res.items.map((x) => ({ ...x.repo, score: x.score, matched: x.matched })),
  };
}
