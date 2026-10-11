import { Router, type Request, type Response } from "express";
import { AppError } from "../util/errors.js";
import { ghAuth, lastRate } from "../github/client.js";
import * as svc from "../github/service.js";
import { reviewPull } from "../github/review.js";
import { graph } from "../github/graph.js";

export const githubRouter = Router();

const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");

function query(req: Request): string {
  const q = str(req.query.q);
  if (!q) throw new AppError(400, "bad_request", "q is required");
  if (q.length > 256) throw new AppError(400, "bad_request", "q is too long");
  return q;
}

/** Sends JSON with the latest GitHub quota in headers. */
async function send(res: Response, data: unknown, resource = "core") {
  const r = await lastRate(resource);
  if (r?.remaining != null) res.setHeader("X-GitHub-RateLimit-Remaining", String(r.remaining));
  if (r?.limit != null) res.setHeader("X-GitHub-RateLimit-Limit", String(r.limit));
  if (r?.resetsAt) res.setHeader("X-GitHub-RateLimit-Reset", r.resetsAt);
  res.setHeader("Cache-Control", "private, max-age=60");
  res.json(data);
}

// Works with the server token (GITHUB_TOKEN) or the caller's connected account.
githubRouter.use(async (_req, _res, next) => {
  if ((await ghAuth()).kind === "none") return next(new AppError(503, "github_disabled", "GitHub is not configured (GITHUB_TOKEN)"));
  next();
});

githubRouter.get("/rate", async (_req, res) => {
  res.json({ core: await lastRate("core"), search: await lastRate("search"), code_search: await lastRate("code_search") });
});

// ---- the caller's connected account (the owner may use the server token) --
githubRouter.get("/me", async (_req, res) => {
  await send(res, await svc.me());
});

const flag = (v: unknown) => ["1", "true"].includes(str(v));

// Every repository the caller can access (cached 5 min; refresh=1 reloads).
githubRouter.get("/my/repos", async (req, res) => {
  await send(
    res,
    await svc.myRepos({ visibility: str(req.query.visibility), sort: str(req.query.sort), perPage: req.query.per_page, refresh: flag(req.query.refresh) }),
  );
});

// The caller's repositories ranked for loose text (typos, partial names, owner words).
githubRouter.get("/my/repos/search", async (req, res) => {
  await send(res, await svc.searchMyRepos(query(req), req.query.limit));
});

// ---- search --------------------------------------------------------------
githubRouter.get("/search/repos", async (req, res) => {
  await send(res, await svc.searchRepos(query(req), str(req.query.sort), req.query.per_page), "search");
});
githubRouter.get("/search/code", async (req, res) => {
  await send(res, await svc.searchCode(query(req), req.query.per_page), "code_search");
});
githubRouter.get("/search/issues", async (req, res) => {
  await send(res, await svc.searchIssues(query(req), req.query.per_page), "search");
});
githubRouter.get("/search/commits", async (req, res) => {
  await send(res, await svc.searchCommits(query(req), req.query.per_page), "search");
});

// ---- repository ---------------------------------------------------------
githubRouter.get("/repos/:owner/:repo", async (req, res) => {
  await send(res, await svc.repoDetail(req.params.owner, req.params.repo));
});

githubRouter.get("/repos/:owner/:repo/commits", async (req, res) => {
  const { owner, repo } = req.params;
  const q = str(req.query.q);
  if (q.length > 256) throw new AppError(400, "bad_request", "q is too long");
  await send(
    res,
    await svc.commitsPage(owner, repo, {
      sha: str(req.query.sha) || str(req.query.branch) || undefined,
      path: str(req.query.path) || undefined,
      author: str(req.query.author) || undefined,
      since: str(req.query.since) || undefined,
      until: str(req.query.until) || undefined,
      q: q || undefined,
      after: str(req.query.after) || undefined,
      perPage: req.query.per_page,
      stats: str(req.query.stats) !== "0",
    }),
    q ? "search" : "core",
  );
});

// Commit DAG of the default branch + recent (or named) branches for the git graph widget.
githubRouter.get("/repos/:owner/:repo/graph", async (req, res) => {
  const ctl = new AbortController();
  res.on("close", () => {
    if (!res.writableFinished) ctl.abort();
  });
  await send(res, await graph(req.params.owner, req.params.repo, { branches: req.query.branches, limit: req.query.limit, after: req.query.after }, ctl.signal));
});

githubRouter.get("/repos/:owner/:repo/commits/:sha", async (req, res) => {
  await send(res, await svc.commit(req.params.owner, req.params.repo, req.params.sha));
});

// `base...head` (two dots also accepted).
githubRouter.get("/repos/:owner/:repo/compare/:spec", async (req, res) => {
  const m = req.params.spec.match(/^(.+?)\.{2,3}(.+)$/);
  if (!m) throw new AppError(400, "bad_request", "Expected base...head");
  await send(res, await svc.compare(req.params.owner, req.params.repo, m[1], m[2]));
});

githubRouter.get("/repos/:owner/:repo/tree/:ref", async (req, res) => {
  const recursive = ["1", "true"].includes(str(req.query.recursive));
  await send(res, await svc.tree(req.params.owner, req.params.repo, req.params.ref, str(req.query.path), recursive));
});

githubRouter.get("/repos/:owner/:repo/contents/:ref", async (req, res) => {
  await send(res, await svc.contents(req.params.owner, req.params.repo, req.params.ref, str(req.query.path)));
});

githubRouter.get("/repos/:owner/:repo/branches", async (req, res) => {
  await send(
    res,
    await svc.branches(req.params.owner, req.params.repo, {
      q: str(req.query.q).slice(0, 120),
      after: str(req.query.after),
      limit: req.query.limit,
      refresh: flag(req.query.refresh),
    }),
  );
});

githubRouter.get("/repos/:owner/:repo/pulls", async (req, res) => {
  await send(res, await svc.pulls(req.params.owner, req.params.repo, req.query.state, req.query.per_page));
});

githubRouter.get("/repos/:owner/:repo/pulls/:n", async (req, res) => {
  await send(res, await svc.pull(req.params.owner, req.params.repo, Number(req.params.n)));
});

// LLM review of the PR's diff (slow: one strong model, cached per head sha).
githubRouter.post("/repos/:owner/:repo/pulls/:n/review", async (req, res) => {
  const ctl = new AbortController();
  res.on("close", () => {
    if (!res.writableFinished) ctl.abort();
  });
  const fresh = ["1", "true"].includes(str(req.query.fresh)) || req.body?.fresh === true;
  const review = await reviewPull(req.params.owner, req.params.repo, Number(req.params.n), { fresh, signal: ctl.signal });
  res.setHeader("Cache-Control", "no-store");
  res.json(review);
});

githubRouter.get("/repos/:owner/:repo/issues", async (req, res) => {
  await send(res, await svc.issues(req.params.owner, req.params.repo, req.query.state, req.query.per_page));
});

githubRouter.get("/repos/:owner/:repo/contributors", async (req, res) => {
  await send(res, await svc.contributors(req.params.owner, req.params.repo, req.query.per_page));
});

githubRouter.get("/repos/:owner/:repo/releases", async (req, res) => {
  await send(res, await svc.releases(req.params.owner, req.params.repo, req.query.per_page));
});
