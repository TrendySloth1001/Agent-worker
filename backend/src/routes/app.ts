import { Router, type NextFunction, type Request, type Response } from "express";
import multer from "multer";
import { db } from "../db/prisma.js";
import { AppError } from "../util/errors.js";
import { requireOwner, runAs, userOf } from "../auth/context.js";
import { createBody, MAX_APK_BYTES, parseOr400, patchBody } from "../ota/logic.js";
import { checkForUpdate, createRelease, deleteRelease, hasReleaseToken, listReleases, patchRelease } from "../ota/service.js";
import { z } from "zod";
import { errorsBody, sessionsBody } from "../ota/errorsLogic.js";
import { ingestErrors, ingestSessions } from "../ota/errorsService.js";
import { rateLimit } from "../util/rateLimit.js";
import { USER_MSG } from "../util/userMessages.js";

/** Behind requireUser: update check for everyone, release management for the owner. */
export const appRouter = Router();
/**
 * Mounted BEFORE requireUser: serves POST /app/releases for a valid RELEASE_TOKEN bearer (acting as owner)
 * and otherwise falls through (next) to the normal auth stack, where the owner route handles it.
 */
export const releaseTokenRouter = Router();

const MULTIPART_SLACK = 64 * 1024;
const APK_TYPES = new Set(["application/vnd.android.package-archive", "application/octet-stream"]);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_APK_BYTES, files: 1, fields: 10, parts: 14 },
  fileFilter: (_req, file, cb) => {
    if (!APK_TYPES.has(file.mimetype)) return cb(new AppError(415, "unsupported_media_type", "Upload an .apk file."));
    cb(null, true);
  },
}).single("apk");

function receive(req: Request, res: Response): Promise<void> {
  return new Promise((resolve, reject) => {
    upload(req, res, (err: unknown) => {
      if (!err) return resolve();
      if (err instanceof multer.MulterError) {
        if (err.code === "LIMIT_FILE_SIZE") return reject(new AppError(413, "payload_too_large", "APK is too large (max 150 MB)."));
        return reject(new AppError(400, "bad_request", "Upload failed."));
      }
      reject(err);
    });
  });
}

async function handleCreate(req: Request, res: Response): Promise<void> {
  db();
  if (!req.is("multipart/form-data")) throw new AppError(400, "bad_request", USER_MSG.uploadFailed);
  const declared = Number(req.headers["content-length"]);
  if (Number.isFinite(declared) && declared > MAX_APK_BYTES + MULTIPART_SLACK) throw new AppError(413, "payload_too_large", "APK is too large (max 150 MB).");
  await receive(req, res);
  const body = parseOr400(createBody, req.body ?? {});
  const f = req.file;
  if (!f || f.size === 0) throw new AppError(400, "bad_request", "Missing apk file");
  // An APK is a zip archive.
  if (f.buffer[0] !== 0x50 || f.buffer[1] !== 0x4b) throw new AppError(400, "bad_request", "That file is not an APK");
  res.json({ release: await createRelease(body, f.buffer) });
}

// Token path: only a matching RELEASE_TOKEN is handled here; everything else continues to requireUser.
releaseTokenRouter.post("/", (req: Request, res: Response, next: NextFunction) => {
  if (!hasReleaseToken(req)) return next("router");
  req.user = { id: null, role: "owner", sid: null, bypass: true };
  runAs(req.user, () => {
    handleCreate(req, res).catch(next);
  });
});

const updateQuery = z.object({ build: z.coerce.number().int().min(0).max(2_000_000_000) });

appRouter.get("/update", async (req, res) => {
  const { build } = parseOr400(updateQuery, req.query);
  const out = await checkForUpdate(build, userOf(req).id);
  res.setHeader("Cache-Control", "private, max-age=300");
  res.json(out);
});

/** Crash/error ingest (OTA v2 phase 2): any signed-in user; the user id always comes from the session, never the body. */
function ingestUser(req: Request): string {
  const id = userOf(req).id;
  if (!id) throw new AppError(403, "forbidden", "Sign in to send reports");
  return id;
}

appRouter.post("/errors", rateLimit(20, 60_000, "auto", { name: "app-errors" }), async (req, res) => {
  const userId = ingestUser(req);
  const { errors } = parseOr400(errorsBody, req.body ?? {});
  res.json(await ingestErrors(userId, errors));
});

appRouter.post("/sessions", rateLimit(30, 60_000, "auto", { name: "app-sessions" }), async (req, res) => {
  const userId = ingestUser(req);
  const { sessions } = parseOr400(sessionsBody, req.body ?? {});
  res.json({ accepted: await ingestSessions(userId, sessions) });
});

appRouter.use("/releases", requireOwner);

appRouter.get("/releases", async (_req, res) => {
  res.setHeader("Cache-Control", "no-store");
  res.json(await listReleases());
});

appRouter.post("/releases", async (req, res) => {
  await handleCreate(req, res);
});

appRouter.patch("/releases/:id", async (req, res) => {
  const body = parseOr400(patchBody, req.body ?? {});
  res.json({ release: await patchRelease(String(req.params.id), body) });
});

appRouter.delete("/releases/:id", async (req, res) => {
  await deleteRelease(String(req.params.id));
  res.status(204).end();
});
