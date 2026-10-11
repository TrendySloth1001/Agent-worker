import { Router, type Request, type Response } from "express";
import { AppError } from "../util/errors.js";
import { githubEnabled, lastRate } from "../github/client.js";
import * as svc from "../github/service.js";
import { reviewPull } from "../github/review.js";

export const githubRouter = Router();

const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");

function query(req: Request): string {
  const q = str(req.query.q);
  if (!q) throw new AppError(400, "bad_request", "q is required");
  if (q.length > 256) throw new AppError(400, "bad_request", "q is too long");
  return q;
}

/** Sends JSON with the latest GitHub quota in headers. */
function send(res: Response, data: unknown, resource = "core") {
  const r = lastRate(resource);
  if (r?.remaining != null) res.setHeader("X-GitHub-RateLimit-Remaining", String(r.remaining));
  if (r?.limit != null) res.setHeader("X-GitHub-RateLimit-Limit", String(r.limit));
  if (r?.resetsAt) res.setHeader("X-GitHub-RateLimit-Reset", r.resetsAt);
  res.setHeader("Cache-Control", "private, max-age=60");
  res.json(data);
}

githubRouter.use((_req, _res, next) => {
  if (!githubEnabled()) return next(new AppError(503, "github_disabled", "GitHub is not configured (GITHUB_TOKEN)"));
  next();
});

githubRouter.get("/rate", (_req, res) => {
  res.json({ core: lastRate("core"), search: lastRate("search"), code_search: lastRate("code_search") });
});

// ---- the token's account (private repos when the token allows) ---------
githubRouter.get("/me", async (_req, res) => {
  send(res, await svc.me());
});

githubRouter.get("/my/repos", async (req, res) => {
  send(res, await svc.myRepos({ visibility: str(req.query.visibility), sort: str(req.query.sort), perPage: req.query.per_page }));
});

// ---- search --------------------------------------------------------------
githubRouter.get("/search/repos", async (req, res) => {
  send(res, await svc.searchRepos(query(req), str(req.query.sort), req.query.per_page), "search");
});
githubRouter.get("/search/code", async (req, res) => {
  send(res, await svc.searchCode(query(req), req.query.per_page), "code_search");
});
githubRouter.get("/search/issues", async (req, res) => {
  send(res, await svc.searchIssues(query(req), req.query.per_page), "search");
});
githubRouter.get("/search/commits", async (req, res) => {
  send(res, await svc.searchCommits(query(req), req.query.per_page), "search");
});

// ---- repository ---------------------------------------------------------
githubRouter.get("/repos/:owner/:repo", async (req, res) => {
  send(res, await svc.repoDetail(req.params.owner, req.params.repo));
});

githubRouter.get("/repos/:owner/:repo/commits", async (req, res) => {
  const { owner, repo } = req.params;
  send(
    res,
    {
      items: await svc.commits(owner, repo, {
        sha: str(req.query.sha) || undefined,
        path: str(req.query.path) || undefined,
        perPage: req.query.per_page,
        stats: str(req.query.stats) !== "0",
      }),
    },
  );
});

githubRouter.get("/repos/:owner/:repo/commits/:sha", async (req, res) => {
  send(res, await svc.commit(req.params.owner, req.params.repo, req.params.sha));
});

// `base...head` (two dots also accepted).
githubRouter.get("/repos/:owner/:repo/compare/:spec", async (req, res) => {
  const m = req.params.spec.match(/^(.+?)\.{2,3}(.+)$/);
  if (!m) throw new AppError(400, "bad_request", "Expected base...head");
  send(res, await svc.compare(req.params.owner, req.params.repo, m[1], m[2]));
});

githubRouter.get("/repos/:owner/:repo/tree/:ref", async (req, res) => {
  const recursive = ["1", "true"].includes(str(req.query.recursive));
  send(res, await svc.tree(req.params.owner, req.params.repo, req.params.ref, str(req.query.path), recursive));
});

githubRouter.get("/repos/:owner/:repo/contents/:ref", async (req, res) => {
  send(res, await svc.contents(req.params.owner, req.params.repo, req.params.ref, str(req.query.path)));
});

githubRouter.get("/repos/:owner/:repo/branches", async (req, res) => {
  send(res, await svc.branches(req.params.owner, req.params.repo));
});

githubRouter.get("/repos/:owner/:repo/pulls", async (req, res) => {
  send(res, await svc.pulls(req.params.owner, req.params.repo, req.query.state, req.query.per_page));
});

githubRouter.get("/repos/:owner/:repo/pulls/:n", async (req, res) => {
  send(res, await svc.pull(req.params.owner, req.params.repo, Number(req.params.n)));
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
  send(res, await svc.issues(req.params.owner, req.params.repo, req.query.state, req.query.per_page));
});

githubRouter.get("/repos/:owner/:repo/contributors", async (req, res) => {
  send(res, await svc.contributors(req.params.owner, req.params.repo, req.query.per_page));
});

githubRouter.get("/repos/:owner/:repo/releases", async (req, res) => {
  send(res, await svc.releases(req.params.owner, req.params.repo, req.query.per_page));
});
