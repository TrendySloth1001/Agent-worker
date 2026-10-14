import { Router } from "express";
import { z } from "zod";
import { requireOwner } from "../auth/context.js";
import { GROUP_STATUSES } from "../ota/errorsLogic.js";
import { parseOr400 } from "../ota/logic.js";
import { buildsHealth, groupDetail, listGroups, setGroupStatus, userOfEvent } from "../ota/errorsService.js";

/** Owner-only crash reporting views. /admin/errors* and /admin/health/builds. */
export const adminErrorsRouter = Router();
adminErrorsRouter.use(requireOwner);

const listQuery = z.object({
  build: z.coerce.number().int().min(0).max(2_000_000_000).optional(),
  status: z.enum([...GROUP_STATUSES, "all"]).default("open"),
  limit: z.coerce.number().int().min(1).max(200).default(50),
});

adminErrorsRouter.get("/", async (req, res) => {
  const q = parseOr400(listQuery, req.query);
  res.setHeader("Cache-Control", "no-store");
  res.json(await listGroups(q));
});

adminErrorsRouter.get("/events/:id/user", async (req, res) => {
  res.setHeader("Cache-Control", "no-store");
  res.json(await userOfEvent(String(req.params.id)));
});

const fingerprint = z.string().regex(/^[0-9a-f]{40}$/);

adminErrorsRouter.get("/:fingerprint", async (req, res) => {
  const fp = parseOr400(fingerprint, req.params.fingerprint);
  res.setHeader("Cache-Control", "no-store");
  res.json(await groupDetail(fp));
});

adminErrorsRouter.patch("/:fingerprint", async (req, res) => {
  const fp = parseOr400(fingerprint, req.params.fingerprint);
  const { status } = parseOr400(z.object({ status: z.enum(GROUP_STATUSES) }), req.body ?? {});
  await setGroupStatus(fp, status);
  res.json({ fingerprint: fp, status });
});

export const adminHealthRouter = Router();
adminHealthRouter.use(requireOwner);

adminHealthRouter.get("/builds", async (req, res) => {
  const { days } = parseOr400(z.object({ days: z.coerce.number().int().min(1).max(90).default(7) }), req.query);
  res.setHeader("Cache-Control", "no-store");
  res.json({ days, builds: await buildsHealth(days) });
});
