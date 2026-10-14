import { Router, type NextFunction, type Request, type Response } from "express";
import multer from "multer";
import { db } from "../db/prisma.js";
import { AppError } from "../util/errors.js";
import { requireOwner, runAs, userOf } from "../auth/context.js";
import { stageApk, stagingKey, type StagedApk } from "../ota/upload.js";
import { eventsBody } from "../ota/events.js";
import { deleteObject } from "../storage/s3.js";
import { rateLimit } from "../util/rateLimit.js";
import { createBody, MAX_APK_BYTES, parseOr400, patchBody } from "../ota/logic.js";
import { checkForUpdate, createRelease, deleteRelease, hasReleaseToken, listReleases, patchRelease, recordInstallEvents } from "../ota/service.js";
import { z } from "zod";
import { errorsBody, sessionsBody } from "../ota/errorsLogic.js";
import { ingestErrors, ingestSessions } from "../ota/errorsService.js";
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

/** multer storage engine: streams the `apk` part straight to S3 (staging key) while hashing; nothing is buffered. */
const streamingStorage: multer.StorageEngine = {
  _handleFile(_req, file, cb) {
    const key = stagingKey();
    stageApk(file.stream, key).then(
      (staged) => cb(null, staged as unknown as Partial<Express.Multer.File>),
      (err: unknown) => {
        deleteObject(key).catch(() => undefined);
        cb(err);
      },
    );
  },
  _removeFile(_req, file, cb) {
    const key = (file as unknown as Partial<StagedApk>).key;
    if (!key) return cb(null);
    deleteObject(key).then(
      () => cb(null),
      () => cb(null),
    );
  },
};

const upload = multer({
  storage: streamingStorage,
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
  const staged = req.file as unknown as StagedApk | undefined;
  try {
    const body = parseOr400(createBody, req.body ?? {});
    if (!staged || staged.size === 0) throw new AppError(400, "bad_request", "Missing apk file");
    res.json({ release: await createRelease(body, staged) });
  } catch (e) {
    // createRelease removes the staged object itself; this covers validation failing before it ran.
    if (staged?.key) await deleteObject(staged.key).catch(() => undefined);
    throw e;
  }
}

// Token path: only a matching RELEASE_TOKEN is handled here; everything else continues to requireUser.
releaseTokenRouter.post("/", (req: Request, res: Response, next: NextFunction) => {
  if (!hasReleaseToken(req)) return next("router");
  req.user = { id: null, role: "owner", sid: null, bypass: true };
  runAs(req.user, () => {
    handleCreate(req, res).catch(next);
  });
});

const updateQuery = z.object({
  build: z.coerce.number().int().min(0).max(2_000_000_000),
  device: z.string().regex(/^[A-Za-z0-9-]{8,64}$/).optional().catch(undefined),
});

appRouter.get("/update", async (req, res) => {
  const { build, device } = parseOr400(updateQuery, req.query);
  const out = await checkForUpdate(build, userOf(req).id, device ?? null);
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

/** Install-outcome events from the app: signed-in users only, user id from the session, batch-capped, rate-limited. */
appRouter.post("/health/events", rateLimit(10, 60_000, "auto", { name: "health-events" }), async (req, res) => {
  const user = userOf(req);
  if (!user.id) throw new AppError(401, "unauthorized", "Sign in required");
  const body = parseOr400(eventsBody, req.body ?? {});
  res.status(202).json({ accepted: await recordInstallEvents(body, user.id) });
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
