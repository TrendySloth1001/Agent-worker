import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { gh, ghAuth, ghGraphql } from "./client.js";
import { checkName } from "./service.js";

/**
 * Commit graph of a repository (the ```github-graph``` widget): the default
 * branch plus a few recently updated branches, merged into one DAG and
 * ordered newest first with children always above their parents. Lanes are
 * laid out by the app.
 */

export type GraphCommit = {
  sha: string;
  parents: string[];
  subject: string;
  author: string;
  authorAvatar: string | null;
  date: string | null;
  /** Branch names whose head is this commit. */
  refs: string[];
};
export type GraphBranch = { name: string; sha: string; isDefault: boolean };
export type Graph = {
  repo: string;
  defaultBranch: string;
  branches: GraphBranch[];
  commits: GraphCommit[];
  truncated: boolean;
  source: "graphql" | "rest";
};

const LIMIT_DEFAULT = 150;
const LIMIT_MAX = 300;
/** Extra branches beside the default one. */
const BRANCHES_MAX = 8;
/** History fetched per non-default branch (most of it overlaps the default). */
const BRANCH_DEPTH = 60;
const CACHE_TTL_MS = 60_000;
const CACHE_MAX = 100;
const BRANCH_RE = /^[\w./+-]{1,120}$/;
const REST_CANDIDATES = 20;

const cache = new Map<string, { at: number; value: Graph }>();

export function parseBranches(v: unknown): string[] {
  if (typeof v !== "string" || !v.trim()) return [];
  const out = v
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  for (const b of out) if (!BRANCH_RE.test(b) || b.includes("..")) throw new AppError(400, "bad_request", "Invalid branch name");
  return [...new Set(out)].slice(0, BRANCHES_MAX);
}

export function clampLimit(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? Math.min(LIMIT_MAX, Math.max(10, Math.round(n))) : LIMIT_DEFAULT;
}

/**
 * Orders commits newest first (committer date) while never placing a commit
 * below one of its parents (git's --date-order). Parents outside the set are
 * ignored for ordering.
 */
export function orderCommits<T extends { sha: string; parents: string[]; date: string | null }>(list: T[]): T[] {
  const bySha = new Map(list.map((c) => [c.sha, c]));
  const pendingChildren = new Map<string, number>();
  for (const c of list) pendingChildren.set(c.sha, 0);
  for (const c of list) {
    for (const p of new Set(c.parents)) if (bySha.has(p)) pendingChildren.set(p, pendingChildren.get(p)! + 1);
  }
  const time = (c: T) => (c.date ? Date.parse(c.date) || 0 : 0);
  // Max-heap on (date, original index) of commits whose children are all placed.
  const heap: { c: T; t: number; i: number }[] = [];
  const index = new Map(list.map((c, i) => [c.sha, i]));
  const before = (a: { t: number; i: number }, b: { t: number; i: number }) => a.t > b.t || (a.t === b.t && a.i < b.i);
  const push = (c: T) => {
    heap.push({ c, t: time(c), i: index.get(c.sha)! });
    let k = heap.length - 1;
    while (k > 0) {
      const up = (k - 1) >> 1;
      if (!before(heap[k], heap[up])) break;
      [heap[k], heap[up]] = [heap[up], heap[k]];
      k = up;
    }
  };
  const pop = () => {
    const top = heap[0];
    const last = heap.pop()!;
    if (heap.length) {
      heap[0] = last;
      let k = 0;
      for (;;) {
        const l = 2 * k + 1;
        const r = l + 1;
        let m = k;
        if (l < heap.length && before(heap[l], heap[m])) m = l;
        if (r < heap.length && before(heap[r], heap[m])) m = r;
        if (m === k) break;
        [heap[k], heap[m]] = [heap[m], heap[k]];
        k = m;
      }
    }
    return top.c;
  };
  for (const c of list) if (pendingChildren.get(c.sha) === 0) push(c);
  const out: T[] = [];
  while (heap.length) {
    const c = pop();
    out.push(c);
    for (const p of new Set(c.parents)) {
      if (!bySha.has(p)) continue;
      const left = pendingChildren.get(p)! - 1;
      pendingChildren.set(p, left);
      if (left === 0) push(bySha.get(p)!);
    }
  }
  // A cycle cannot happen in git; keep anything left over just in case.
  if (out.length < list.length) {
    const seen = new Set(out.map((c) => c.sha));
    for (const c of list) if (!seen.has(c.sha)) out.push(c);
  }
  return out;
}

/** Merges per-branch histories into one capped, ordered graph. */
export function buildGraph(
  repo: string,
  defaultBranch: string,
  branches: GraphBranch[],
  histories: GraphCommit[][],
  limit: number,
  moreHistory: boolean,
  source: Graph["source"],
): Graph {
  const all = new Map<string, GraphCommit>();
  for (const h of histories) for (const c of h) if (!all.has(c.sha)) all.set(c.sha, { ...c, refs: [] });
  for (const b of branches) all.get(b.sha)?.refs.push(b.name);
  const ordered = orderCommits([...all.values()]);
  return {
    repo,
    defaultBranch,
    branches,
    commits: ordered.slice(0, limit),
    truncated: moreHistory || ordered.length > limit,
    source,
  };
}

// ---- GraphQL ---------------------------------------------------------------

const COMMIT_FIELDS = `oid messageHeadline committedDate parents(first: 8) { nodes { oid } } author { name user { login avatarUrl } }`;
const HISTORY = (n: string) => `... on Commit { oid history(first: ${n}) { pageInfo { hasNextPage endCursor } nodes { ${COMMIT_FIELDS} } } }`;
/** GitHub caps `first` at 100 per connection. */
const PAGE_MAX = 100;

type GqlCommit = {
  oid: string;
  messageHeadline: string;
  committedDate: string;
  parents: { nodes: { oid: string }[] };
  author: { name: string | null; user: { login: string; avatarUrl: string } | null } | null;
};
type GqlHistory = { pageInfo: { hasNextPage: boolean; endCursor: string | null }; nodes: GqlCommit[] };
type GqlRef = { name: string; target: { oid: string; history?: GqlHistory } | null } | null;

const fromGql = (c: GqlCommit): GraphCommit => ({
  sha: c.oid,
  parents: c.parents.nodes.map((p) => p.oid),
  subject: c.messageHeadline.slice(0, 200),
  author: c.author?.user?.login ?? c.author?.name ?? "",
  authorAvatar: c.author?.user?.avatarUrl ?? null,
  date: c.committedDate ?? null,
  refs: [],
});

const REFS_PAGES = 2;
/** Candidates asked for: some may have been deleted since they were pushed. */
const CANDIDATES = BRANCHES_MAX + 4;
const SKIP_BRANCH = /^(gh-readonly-queue|dependabot)\//;

/**
 * Recently pushed branches, newest first, from the repository activity feed
 * (deleted, merge-queue and default branches skipped).
 */
async function activeBranches(owner: string, repo: string, def: string, n: number, signal?: AbortSignal): Promise<string[]> {
  const list = await gh<any[]>(`/repos/${owner}/${repo}/activity?per_page=100&direction=desc`, { signal, ttlMs: CACHE_TTL_MS });
  const seen = new Set<string>();
  const out: string[] = [];
  for (const a of Array.isArray(list) ? list : []) {
    const ref = String(a?.ref ?? "");
    if (!ref.startsWith("refs/heads/")) continue;
    const name = ref.slice("refs/heads/".length);
    if (seen.has(name)) continue;
    seen.add(name);
    // The newest event decides: a deletion means the branch is gone.
    if (a.activity_type === "branch_deletion" || name === def || SKIP_BRANCH.test(name)) continue;
    out.push(name);
    if (out.length >= n) break;
  }
  return out;
}

/** Fallback: branch heads by commit date (GitHub cannot sort refs by date; first pages only). */
async function datedBranches(owner: string, repo: string, def: string, n: number, signal?: AbortSignal): Promise<string[]> {
  const query = `query($owner: String!, $name: String!, $after: String) {
    repository(owner: $owner, name: $name) {
      refs(refPrefix: "refs/heads/", first: 100, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes { name target { ... on Commit { committedDate } } }
      }
    }
  }`;
  const heads: { name: string; t: number }[] = [];
  let after: string | null = null;
  for (let page = 0; page < REFS_PAGES; page++) {
    const d: any = await ghGraphql(query, { owner, name: repo, after }, { signal });
    const refs = d?.repository?.refs;
    for (const x of refs?.nodes ?? []) heads.push({ name: x.name, t: Date.parse(x.target?.committedDate ?? "") || 0 });
    if (!refs?.pageInfo?.hasNextPage) break;
    after = refs.pageInfo.endCursor;
  }
  return heads
    .filter((h) => h.name !== def && !SKIP_BRANCH.test(h.name))
    .sort((a, b) => b.t - a.t)
    .slice(0, n)
    .map((h) => h.name);
}

async function recentBranches(owner: string, repo: string, signal?: AbortSignal): Promise<string[]> {
  const r = await gh(`/repos/${owner}/${repo}`, { signal });
  const def = String(r.default_branch ?? "");
  const active = await activeBranches(owner, repo, def, CANDIDATES, signal).catch((e) => {
    log.info("github graph: no activity feed", { message: (e as Error).message.slice(0, 80) });
    return [] as string[];
  });
  if (active.length) return active;
  return datedBranches(owner, repo, def, CANDIDATES, signal);
}

async function viaGraphql(owner: string, repo: string, requested: string[], limit: number, signal?: AbortSignal): Promise<Graph> {
  const wanted = requested.length ? requested : await recentBranches(owner, repo, signal);
  const depth = Math.min(limit, BRANCH_DEPTH, PAGE_MAX);
  const named = wanted.map((_, i) => `b${i}: ref(qualifiedName: $q${i}) { name target { ${HISTORY("$depth")} } }`).join("\n");
  const vars = (wanted.length ? ", $depth: Int!" : "") + wanted.map((_, i) => `, $q${i}: String!`).join("");
  const query = `query($owner: String!, $name: String!, $limit: Int!${vars}) {
    repository(owner: $owner, name: $name) {
      nameWithOwner
      defaultBranchRef { name target { ${HISTORY("$limit")} } }
      ${named}
    }
  }`;
  const variables: Record<string, unknown> = { owner, name: repo, limit: Math.min(limit, PAGE_MAX) };
  if (wanted.length) variables.depth = depth;
  wanted.forEach((b, i) => (variables[`q${i}`] = `refs/heads/${b}`));
  const d = await ghGraphql<{ repository: any }>(query, variables, { signal });
  const r = d?.repository;
  if (!r) throw new AppError(404, "not_found", "GitHub: not found (or private)");
  const def = r.defaultBranchRef as GqlRef;
  if (!def?.target?.history) return buildGraph(r.nameWithOwner, def?.name ?? "", [], [], limit, false, "graphql");
  const refs = wanted.map((_, i) => r[`b${i}`] as GqlRef);
  const others = refs.filter((x): x is NonNullable<GqlRef> => !!x?.target?.history && x.name !== def.name).slice(0, BRANCHES_MAX);
  const branches: GraphBranch[] = [
    { name: def.name, sha: def.target!.oid, isDefault: true },
    ...others.map((x) => ({ name: x.name, sha: x.target!.oid, isDefault: false })),
  ];
  // The default branch beyond the first page.
  const main = [...def.target.history.nodes];
  let page = def.target.history.pageInfo;
  while (main.length < limit && page.hasNextPage && page.endCursor) {
    const next = await ghGraphql<{ repository: { object: { history: GqlHistory } | null } | null }>(
      `query($owner: String!, $name: String!, $oid: GitObjectID!, $n: Int!, $after: String!) {
        repository(owner: $owner, name: $name) { object(oid: $oid) { ... on Commit { history(first: $n, after: $after) { pageInfo { hasNextPage endCursor } nodes { ${COMMIT_FIELDS} } } } } }
      }`,
      { owner, name: repo, oid: def.target.oid, n: Math.min(PAGE_MAX, limit - main.length), after: page.endCursor },
      { signal },
    );
    const h = next?.repository?.object?.history;
    if (!h) break;
    main.push(...h.nodes);
    page = h.pageInfo;
  }
  const histories = [main.map(fromGql), ...others.map((x) => x.target!.history!.nodes.map(fromGql))];
  return buildGraph(r.nameWithOwner, def.name, branches, histories, limit, !!page.hasNextPage, "graphql");
}

// ---- REST fallback -----------------------------------------------------------

const fromRest = (c: any): GraphCommit => ({
  sha: c.sha,
  parents: (c.parents ?? []).map((p: any) => p.sha),
  subject: String(c.commit?.message ?? "").split("\n")[0].slice(0, 200),
  author: c.author?.login ?? c.commit?.author?.name ?? "",
  authorAvatar: c.author?.avatar_url ?? null,
  date: c.commit?.committer?.date ?? c.commit?.author?.date ?? null,
  refs: [],
});

async function restHistory(base: string, sha: string, n: number, signal?: AbortSignal): Promise<{ list: GraphCommit[]; more: boolean }> {
  // A fixed page size keeps page offsets aligned.
  const per = Math.min(100, n);
  const out: GraphCommit[] = [];
  for (let page = 1; ; page++) {
    const list = await gh<any[]>(`${base}/commits?sha=${encodeURIComponent(sha)}&per_page=${per}&page=${page}`, { signal, ttlMs: CACHE_TTL_MS });
    out.push(...list.map(fromRest));
    if (list.length < per) return { list: out.slice(0, n), more: false };
    if (out.length >= n) return { list: out.slice(0, n), more: true };
  }
}

/** Activity-feed branches that still exist in [all] (the first branches page). */
async function activeHeads(base: string, def: string, all: any[], signal?: AbortSignal): Promise<{ name: string; sha: string }[]> {
  const [, owner, repo] = base.split("/").slice(1);
  const names = await activeBranches(owner, repo, def, CANDIDATES, signal).catch(() => [] as string[]);
  const out: { name: string; sha: string }[] = [];
  for (const name of names) {
    const known = all.find((b) => b.name === name);
    const b = known ?? (await gh(`${base}/branches/${encodeURIComponent(name)}`, { allow404: true, signal }).catch(() => null));
    if (b?.commit?.sha) out.push({ name, sha: b.commit.sha });
    if (out.length >= BRANCHES_MAX) break;
  }
  return out;
}

async function viaRest(owner: string, repo: string, wanted: string[], limit: number, signal?: AbortSignal): Promise<Graph> {
  const r = await gh(`/repos/${owner}/${repo}`, { signal });
  const base = `/repos/${r.full_name}`;
  const def: string = r.default_branch;
  const all = await gh<any[]>(`${base}/branches?per_page=100`, { signal }).catch(() => [] as any[]);
  let picked: { name: string; sha: string }[] = [];
  if (wanted.length) {
    picked = (
      await Promise.all(
        wanted
          .filter((b) => b !== def)
          .map((b) => gh(`${base}/branches/${encodeURIComponent(b)}`, { allow404: true, signal }).catch(() => null)),
      )
    )
      .filter(Boolean)
      .map((b: any) => ({ name: b.name, sha: b.commit?.sha ?? "" }));
  } else if ((picked = await activeHeads(base, def, all, signal)).length) {
    // Recently pushed branches from the activity feed.
  } else {
    // REST lists branches by name: date the heads to find the recent ones.
    const cands = all.filter((b) => b.name !== def).slice(0, REST_CANDIDATES);
    const dated = await Promise.all(
      cands.map(async (b) => {
        const c = await gh(`${base}/git/commits/${b.commit?.sha}`, { signal }).catch(() => null);
        return { name: b.name as string, sha: (b.commit?.sha as string) ?? "", t: c?.committer?.date ? Date.parse(c.committer.date) : 0 };
      }),
    );
    picked = dated.sort((a, b) => b.t - a.t).slice(0, BRANCHES_MAX);
  }
  const depth = Math.min(limit, BRANCH_DEPTH);
  const [main, ...rest] = await Promise.all([
    restHistory(base, def, limit, signal),
    ...picked.map((b) => restHistory(base, b.sha, depth, signal).catch(() => ({ list: [], more: false }))),
  ]);
  const defSha = all.find((b) => b.name === def)?.commit?.sha ?? main.list[0]?.sha ?? "";
  const branches: GraphBranch[] = [{ name: def, sha: defSha, isDefault: true }, ...picked.map((b) => ({ ...b, isDefault: false }))];
  return buildGraph(r.full_name, def, branches, [main.list, ...rest.map((x) => x.list)], limit, main.more, "rest");
}

// ---- entry -------------------------------------------------------------------

export async function graph(owner: string, repo: string, q: { branches?: unknown; limit?: unknown }, signal?: AbortSignal): Promise<Graph> {
  checkName(owner, repo);
  const wanted = parseBranches(q.branches);
  const limit = clampLimit(q.limit);
  const auth = await ghAuth();
  const key = `${auth.key}|${owner.toLowerCase()}/${repo.toLowerCase()}|${wanted.join(",")}|${limit}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < CACHE_TTL_MS) return hit.value;

  let value: Graph;
  if (auth.token) {
    try {
      value = await viaGraphql(owner, repo, wanted, limit, signal);
    } catch (e) {
      const status = (e as AppError).status;
      // Missing repo, rate limit, revoked token: REST would fail the same way.
      if (status === 404 || status === 409 || status === 429 || signal?.aborted) throw e;
      log.warn("github graph: graphql failed, using REST", { message: (e as Error).message.slice(0, 120) });
      value = await viaRest(owner, repo, wanted, limit, signal);
    }
  } else {
    value = await viaRest(owner, repo, wanted, limit, signal);
  }
  cache.delete(key);
  cache.set(key, { at: Date.now(), value });
  while (cache.size > CACHE_MAX) cache.delete(cache.keys().next().value!);
  return value;
}
