import { Router } from "express";
import { AppError } from "../util/errors.js";
import { imagesForQuery } from "../web/images.js";

export const imagesRouter = Router();

// GET /images/search?q=<description>&n=<1..4>
imagesRouter.get("/search", async (req, res) => {
  const q = typeof req.query.q === "string" ? req.query.q.trim().slice(0, 120) : "";
  if (!q) throw new AppError(400, "bad_request", "q is required");
  const n = Math.min(Math.max(Number(req.query.n) || 1, 1), 4);
  res.json({ images: await imagesForQuery(q, n) });
});
