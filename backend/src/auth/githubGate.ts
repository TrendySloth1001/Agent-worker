import type { NextFunction, Request, Response } from "express";
import { repoRaw } from "../github/service.js";
import { AppError } from "../util/errors.js";

/**
 * /github uses the server's token, which belongs to the owner. Other users
 * get public GitHub features only: no /me or /my/*, and a private repository
 * reads as not found.
 */
export async function githubGate(req: Request, _res: Response, next: NextFunction): Promise<void> {
  if (req.user?.role === "owner") return next();
  if (/^\/(me|my)(\/|$)/.test(req.path)) return next(new AppError(403, "owner_only", "Only the owner's GitHub account is connected"));
  const m = req.path.match(/^\/repos\/([^/]+)\/([^/]+)/);
  if (m) {
    const r = await repoRaw(decodeURIComponent(m[1]), decodeURIComponent(m[2])).catch(() => null);
    if (r?.private) return next(new AppError(404, "not_found", "Repository not found"));
  }
  next();
}
