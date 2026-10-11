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
  /** Older history exists (same as nextCursor != null on paged responses). */
  truncated: boolean;
  source: "graphql" | "rest";
  /** Pass back as `after` for the next (older) page; null when every branch is exhausted. */
  nextCursor: string | null;
  /** Commits on the default branch plus those only on the shown branches (null when unknown). */
  totalCount: number | null;
};

const LIMIT_DEFAULT = 150;
const LIMIT_MAX = 300;
/** Branches a request may name (the picker's "all branches" sends the most recent ones). */
export const BRANCHES_MAX = 25;
/** Recently pushed branches shown when none are named. */
const BRANCHES_RECENT = 8;
const CACHE_TTL_MS = 60_000;
const CACHE_MAX = 100;
const BRANCH_RE = /^[\w./+-]{1,120}$/;
const REST_CANDIDATES = 20;
/** Rounds of per-branch pages fetched for one response. */
const ROUNDS_MAX = 4;

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
    nextCursor: null,
    totalCount: null,
  };
}

// ---- GraphQL ---------------------------------------------------------------

const COMMIT_FIELDS = `oid messageHeadline committedDate parents(first: 8) { nodes { oid } } author { name user { login avatarUrl } }`;
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

const fromRest = (c: any): GraphCommit => ({
  sha: c.sha,
  parents: (c.parents ?? []).map((p: any) => p.sha),
  subject: String(c.commit?.message ?? "").split("\n")[0].slice(0, 200),
  author: c.author?.login ?? c.commit?.author?.name ?? "",
  authorAvatar: c.author?.avatar_url ?? null,
  date: c.commit?.committer?.date ?? c.commit?.author?.date ?? null,
  refs: [],
});

// ---- paging ------------------------------------------------------------------
//
// Every branch is a stream of its history (newest first), resumed from a
// position: a GraphQL edge cursor or, over REST, an offset. A page merges the
// streams like a k-way merge on commit date: a commit is only emitted once no
// unfetched commit of another stream can be newer (the horizon), so pages
// never need re-sorting and children stay above parents across pages. A
// non-default branch stops after the commits it has beyond the default branch
// (compare aheadBy) since the rest is the default branch's own history.

type Stream = {
  /** Branch name and pinned head sha (stable while paging). */
  n: string;
  o: string;
  d?: 1;
  /** GraphQL cursor (null = from the head). */
  a?: string | null;
  /** REST offset. */
  k?: number;
  /** Commits still worth emitting (aheadBy + 1); undefined = unbounded. */
  r?: number;
  x?: 1;
};
type Cursor = { v: 1; s: Graph["source"]; repo: string; def: string; t: number | null; b: Stream[] };

export function encodeCursor(c: Cursor): string {
  return Buffer.from(JSON.stringify(c)).toString("base64url");
}

export function decodeCursor(v: unknown, owner: string, repo: string): Cursor | null {
  if (typeof v !== "string" || !v) return null;
  try {
    const c = JSON.parse(Buffer.from(v, "base64url").toString("utf8")) as Cursor;
    if (c?.v !== 1 || !Array.isArray(c.b) || typeof c.repo !== "string") throw new Error("shape");
    if (c.repo.toLowerCase() !== `${owner}/${repo}`.toLowerCase()) throw new Error("repo");
    for (const b of c.b) if (typeof b.n !== "string" || !/^[0-9a-f]{40}$/i.test(String(b.o))) throw new Error("stream");
    return c;
  } catch {
    throw new AppError(400, "bad_request", "Invalid cursor");
  }
}

type Fetched = { items: { c: GraphCommit; pos: string | number }[]; more: boolean; total?: number };
const time = (c: GraphCommit) => (c.date ? Date.parse(c.date) || 0 : 0);

/**
 * One merge step over [fetched] (same order as [streams]): the commits to
 * emit and each stream's new position. Pure, for tests.
 */
export function mergeStep(streams: Stream[], fetched: Fetched[]): { emitted: GraphCommit[]; streams: Stream[] } {
  let horizon = -Infinity;
  let lead = -1;
  fetched.forEach((f, i) => {
    if (!f.more || !f.items.length) return;
    const t = time(f.items[f.items.length - 1].c);
    if (t > horizon) [horizon, lead] = [t, i];
  });
  const emitted: GraphCommit[] = [];
  const next = streams.map((s, i) => {
    const f = fetched[i];
    if (!f) return s;
    let take = f.items.length;
    if (f.more && i !== lead) {
      take = 0;
      while (take < f.items.length && time(f.items[take].c) >= horizon) take++;
    }
    if (s.r != null) take = Math.min(take, s.r);
    const part = f.items.slice(0, take);
    emitted.push(...part.map((x) => x.c));
    const out: Stream = { ...s };
    if (take > 0) {
      const pos = part[take - 1].pos;
      if (typeof pos === "number") out.k = pos;
      else out.a = pos;
    }
    if (out.r != null) out.r -= take;
    if ((!f.more && take === f.items.length) || (out.r != null && out.r <= 0)) out.x = 1;
    return out;
  });
  return { emitted, streams: next };
}

type Source = {
  kind: Graph["source"];
  fetch(streams: Stream[], n: number, withTotal: boolean): Promise<Fetched[]>;
};

const EDGE_FIELDS = `pageInfo { hasNextPage } edges { cursor node { ${COMMIT_FIELDS} } }`;

function gqlSource(owner: string, repo: string, signal?: AbortSignal): Source {
  return {
    kind: "graphql",
    async fetch(streams, n, withTotal) {
      const vars: Record<string, unknown> = { owner, name: repo };
      const decl: string[] = [];
      const parts = streams.map((s, i) => {
        decl.push(`$o${i}: GitObjectID!`, `$a${i}: String`, `$n${i}: Int!`);
        vars[`o${i}`] = s.o;
        vars[`a${i}`] = s.a ?? null;
        vars[`n${i}`] = Math.max(1, Math.min(PAGE_MAX, n, s.r ?? PAGE_MAX));
        const total = withTotal && s.d ? "totalCount" : "";
        return `s${i}: object(oid: $o${i}) { ... on Commit { history(first: $n${i}, after: $a${i}) { ${total} ${EDGE_FIELDS} } } }`;
      });
      const d = await ghGraphql<{ repository: Record<string, any> | null }>(
        `query($owner: String!, $name: String!, ${decl.join(", ")}) { repository(owner: $owner, name: $name) { ${parts.join("\n")} } }`,
        vars,
        { signal, partial: true },
      );
      if (!d?.repository) throw new AppError(404, "not_found", "GitHub: not found (or private)");
      return streams.map((_, i) => {
        const h = d.repository![`s${i}`]?.history;
        if (!h) return { items: [], more: false };
        return {
          items: (h.edges ?? []).map((e: any) => ({ c: fromGql(e.node), pos: e.cursor as string })),
          more: !!h.pageInfo?.hasNextPage,
          total: typeof h.totalCount === "number" ? h.totalCount : undefined,
        };
      });
    },
  };
}

const REST_PAGE = 100;

function restSource(base: string, signal?: AbortSignal): Source {
  return {
    kind: "rest",
    async fetch(streams, n) {
      return Promise.all(
        streams.map(async (s) => {
          const k = s.k ?? 0;
          const page = Math.floor(k / REST_PAGE) + 1;
          const list = await gh<any[]>(`${base}/commits?sha=${s.o}&per_page=${REST_PAGE}&page=${page}`, { signal, ttlMs: CACHE_TTL_MS }).catch(
            () => [] as any[],
          );
          const skip = k % REST_PAGE;
          const want = Math.min(n, s.r ?? n);
          const items = list.slice(skip, skip + want).map((c, j) => ({ c: fromRest(c), pos: k + j + 1 }));
          const more = skip + items.length < list.length || list.length === REST_PAGE;
          return { items, more };
        }),
      );
    },
  };
}

/** Runs merge rounds until [limit] new commits are out or every stream is done. */
async function page(src: Source, cur: Cursor, limit: number, first: boolean): Promise<Graph> {
  const bySha = new Map<string, GraphCommit>();
  let streams = cur.b;
  let total = cur.t;
  for (let round = 0; round < ROUNDS_MAX && bySha.size < limit; round++) {
    const active = streams.map((s, i) => [s, i] as const).filter(([s]) => !s.x);
    if (!active.length) break;
    const n = Math.min(PAGE_MAX, Math.max(10, limit - bySha.size));
    const fetched = await src.fetch(
      active.map(([s]) => s),
      n,
      first && round === 0,
    );
    if (first && round === 0) {
      const def = fetched.find((_, j) => active[j][0].d);
      if (def?.total != null) total = def.total + (total ?? 0);
    }
    const step = mergeStep(
      active.map(([s]) => s),
      fetched,
    );
    // A branch without a known merge base stops once it reaches commits of the default branch.
    const defShas = new Set<string>();
    fetched.forEach((f, j) => active[j][0].d && f.items.forEach((x) => defShas.add(x.c.sha)));
    step.streams.forEach((s, j) => {
      if (!s.d && s.r == null && fetched[j].items.some((x) => defShas.has(x.c.sha))) s.x = 1;
    });
    const updated = [...streams];
    active.forEach(([, i], j) => (updated[i] = step.streams[j]));
    streams = updated;
    for (const c of step.emitted) if (!bySha.has(c.sha)) bySha.set(c.sha, c);
  }
  const done = streams.every((s) => s.x);
  const next: Cursor = { ...cur, t: total, b: streams };
  const branches: GraphBranch[] = cur.b.map((s) => ({ name: s.n, sha: s.o, isDefault: !!s.d }));
  const commits = [...bySha.values()].map((c) => ({ ...c, refs: [] as string[] }));
  const at = new Map(commits.map((c) => [c.sha, c]));
  for (const b of branches) at.get(b.sha)?.refs.push(b.name);
  return {
    repo: cur.repo,
    defaultBranch: cur.def,
    branches,
    commits: orderCommits(commits),
    truncated: !done,
    source: src.kind,
    nextCursor: done ? null : encodeCursor(next),
    totalCount: total,
  };
}

// ---- first page: which branches --------------------------------------------

const REFS_PAGES = 2;
/** Candidates asked for: some may have been deleted since they were pushed. */
const CANDIDATES = BRANCHES_RECENT + 4;
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
  for (let p = 0; p < REFS_PAGES; p++) {
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

async function recentBranches(owner: string, repo: string, def: string, signal?: AbortSignal): Promise<string[]> {
  const active = await activeBranches(owner, repo, def, CANDIDATES, signal).catch((e) => {
    log.info("github graph: no activity feed", { message: (e as Error).message.slice(0, 80) });
    return [] as string[];
  });
  if (active.length) return active;
  return datedBranches(owner, repo, def, CANDIDATES, signal).catch(() => [] as string[]);
}

/** Default branch, the named (or recent) branches with pinned heads, and how far each is ahead. */
async function startGql(owner: string, repo: string, requested: string[], signal?: AbortSignal): Promise<Cursor> {
  const meta = await ghGraphql<{ repository: any }>(
    `query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { nameWithOwner defaultBranchRef { name target { oid } } } }`,
    { owner, name: repo },
    { signal },
  );
  const r = meta?.repository;
  if (!r) throw new AppError(404, "not_found", "GitHub: not found (or private)");
  const def = r.defaultBranchRef as { name: string; target: { oid: string } | null } | null;
  if (!def?.target) return { v: 1, s: "graphql", repo: r.nameWithOwner, def: def?.name ?? "", t: 0, b: [] };
  const wanted = (requested.length ? requested : await recentBranches(owner, repo, def.name, signal))
    .filter((b) => b !== def.name)
    .slice(0, requested.length ? BRANCHES_MAX : CANDIDATES);
  const streams: Stream[] = [{ n: def.name, o: def.target.oid, d: 1, a: null }];
  let total: number | null = 0;
  if (wanted.length) {
    const vars: Record<string, unknown> = { owner, name: repo };
    const decl = wanted.map((_, i) => `$q${i}: String!`).join(", ");
    wanted.forEach((b, i) => (vars[`q${i}`] = `refs/heads/${b}`));
    const d = await ghGraphql<{ repository: any }>(
      `query($owner: String!, $name: String!, ${decl}) { repository(owner: $owner, name: $name) {
        ${wanted.map((_, i) => `b${i}: ref(qualifiedName: $q${i}) { name target { oid } }`).join("\n")}
        defaultBranchRef { ${wanted.map((_, i) => `c${i}: compare(headRef: $q${i}) { aheadBy }`).join("\n")} }
      } }`,
      vars,
      { signal, partial: true },
    );
    const rr = d?.repository ?? {};
    let shown = 0;
    wanted.forEach((_, i) => {
      const ref = rr[`b${i}`];
      if (!ref?.target?.oid || (!requested.length && shown >= BRANCHES_RECENT)) return;
      shown++;
      const ahead = rr.defaultBranchRef?.[`c${i}`]?.aheadBy;
      const s: Stream = { n: ref.name, o: ref.target.oid, a: null };
      if (typeof ahead === "number") {
        s.r = ahead + 1;
        if (total != null) total += ahead;
      } else total = null;
      streams.push(s);
    });
  }
  return { v: 1, s: "graphql", repo: r.nameWithOwner, def: def.name, t: total, b: streams };
}

async function startRest(owner: string, repo: string, requested: string[], signal?: AbortSignal): Promise<Cursor> {
  const r = await gh(`/repos/${owner}/${repo}`, { signal });
  const base = `/repos/${r.full_name}`;
  const def: string = r.default_branch;
  const head = await gh(`${base}/branches/${encodeURIComponent(def)}`, { allow404: true, signal }).catch(() => null);
  if (!head?.commit?.sha) return { v: 1, s: "rest", repo: r.full_name, def, t: 0, b: [] };
  let names = requested.filter((b) => b !== def).slice(0, BRANCHES_MAX);
  if (!names.length && !requested.length) {
    names = await activeBranches(owner, repo, def, CANDIDATES, signal).catch(() => [] as string[]);
    if (!names.length) {
      // REST lists branches by name: date the heads to find the recent ones.
      const all = await gh<any[]>(`${base}/branches?per_page=100`, { signal }).catch(() => [] as any[]);
      const dated = await Promise.all(
        all
          .filter((b) => b.name !== def)
          .slice(0, REST_CANDIDATES)
          .map(async (b) => {
            const c = await gh(`${base}/git/commits/${b.commit?.sha}`, { signal }).catch(() => null);
            return { name: b.name as string, t: c?.committer?.date ? Date.parse(c.committer.date) : 0 };
          }),
      );
      names = dated.sort((a, b) => b.t - a.t).map((b) => b.name);
    }
    names = names.slice(0, CANDIDATES);
  }
  const heads = await Promise.all(
    names.map((b) => gh(`${base}/branches/${encodeURIComponent(b)}`, { allow404: true, signal }).catch(() => null)),
  );
  const picked = heads.filter((b: any) => b?.commit?.sha).slice(0, requested.length ? BRANCHES_MAX : BRANCHES_RECENT);
  const ahead = await Promise.all(
    picked.map((b: any) =>
      gh(`${base}/compare/${encodeURIComponent(def)}...${b.commit.sha}`, { signal })
        .then((c) => (typeof c?.ahead_by === "number" ? (c.ahead_by as number) : null))
        .catch(() => null),
    ),
  );
  let total: number | null = null;
  const streams: Stream[] = [
    { n: def, o: head.commit.sha, d: 1, k: 0 },
    ...picked.map((b: any, i) => {
      const s: Stream = { n: b.name, o: b.commit.sha, k: 0 };
      if (ahead[i] != null) s.r = ahead[i]! + 1;
      return s;
    }),
  ];
  return { v: 1, s: "rest", repo: r.full_name, def, t: total, b: streams };
}

// ---- entry -------------------------------------------------------------------

export async function graph(
  owner: string,
  repo: string,
  q: { branches?: unknown; limit?: unknown; after?: unknown },
  signal?: AbortSignal,
): Promise<Graph> {
  checkName(owner, repo);
  const limit = clampLimit(q.limit);
  const after = decodeCursor(q.after, owner, repo);
  const wanted = after ? [] : parseBranches(q.branches);
  const auth = await ghAuth();
  const key = `${auth.key}|${owner.toLowerCase()}/${repo.toLowerCase()}|${wanted.join(",")}|${limit}|${typeof q.after === "string" ? q.after : ""}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < CACHE_TTL_MS) return hit.value;

  let value: Graph;
  if (after) {
    const src = after.s === "graphql" && auth.token ? gqlSource(owner, repo, signal) : restSource(`/repos/${after.repo}`, signal);
    value = await page(src, after, limit, false);
  } else if (auth.token) {
    try {
      const cur = await startGql(owner, repo, wanted, signal);
      value = await page(gqlSource(owner, repo, signal), cur, limit, true);
    } catch (e) {
      const status = (e as AppError).status;
      // Missing repo, rate limit, revoked token: REST would fail the same way.
      if (status === 404 || status === 409 || status === 429 || signal?.aborted) throw e;
      log.warn("github graph: graphql failed, using REST", { message: (e as Error).message.slice(0, 120) });
      const cur = await startRest(owner, repo, wanted, signal);
      value = await page(restSource(`/repos/${cur.repo}`, signal), cur, limit, true);
    }
  } else {
    const cur = await startRest(owner, repo, wanted, signal);
    value = await page(restSource(`/repos/${cur.repo}`, signal), cur, limit, true);
  }
  cache.delete(key);
  cache.set(key, { at: Date.now(), value });
  while (cache.size > CACHE_MAX) cache.delete(cache.keys().next().value!);
  return value;
}
