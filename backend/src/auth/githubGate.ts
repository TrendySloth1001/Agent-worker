import type { NextFunction, Request, Response } from "express";
import { ghAuth } from "../github/client.js";
import { repoRaw } from "../github/service.js";
import { AppError } from "../util/errors.js";

/**
 * /github calls run with the caller's own GitHub token once they connected
 * their account (POST /connections/github/device). Without a connection the
 * server's token (the owner's) is used: in full for the owner, public data
 * only for everyone else (no /me or /my/*, and a private repository reads as
 * not found).
 */
export async function githubGate(req: Request, _res: Response, next: NextFunction): Promise<void> {
  const auth = await ghAuth();
  if (/^\/(me|my)(\/|$)/.test(req.path)) {
    if (auth.kind === "user" || (auth.kind === "server" && !auth.publicOnly)) return next();
    return next(new AppError(409, "github_not_connected", "Connect your GitHub account first"));
  }
  if (!auth.publicOnly) return next();
  const m = req.path.match(/^\/repos\/([^/]+)\/([^/]+)/);
  if (m) {
    const r = await repoRaw(decodeURIComponent(m[1]), decodeURIComponent(m[2])).catch(() => null);
    if (r?.private) return next(new AppError(404, "not_found", "Repository not found"));
  }
  next();
}
