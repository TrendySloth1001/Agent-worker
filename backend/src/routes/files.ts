import { randomUUID } from "node:crypto";
import { Router, type Request, type Response } from "express";
import multer from "multer";
import { db } from "../db/prisma.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { classify, MAX_UPLOAD_BYTES, SIZE_LIMITS } from "../files/kinds.js";
import pLimit from "p-limit";
import { z } from "zod";
import { config } from "../config.js";
import { deleteFile, getFileRow, INFO_SELECT, markAttachments, signedInfo, toFileRow } from "../files/store.js";
import { cleanRename, listFiles, parseListQuery, usageByKind } from "../files/library.js";
import { processFile } from "../files/process.js";
import { putObject } from "../storage/s3.js";
import { userOf } from "../auth/context.js";
import { checkUpload, limitsFor, recordUpload, resetsAt, usageFor } from "../auth/limits.js";

export const filesRouter = Router();

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** busboy reads names as latin1; recover UTF-8 names. */
function fixName(raw: string): string {
  const decoded = Buffer.from(raw, "latin1").toString("utf8");
  const name = decoded.includes("�") ? raw : decoded;
  return (name.split(/[\\/]/).pop() ?? "file").replace(/[\u0000-\u001f]/g, "").trim().slice(0, 200) || "file";
}

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_UPLOAD_BYTES, files: 1, fields: 5, parts: 8 },
  fileFilter: (_req, file, cb) => {
    const name = fixName(file.originalname);
    if (!classify(name, file.mimetype)) {
      return cb(new AppError(415, "unsupported_media_type", `Unsupported file type: ${name.split(".").pop() || file.mimetype}`));
    }
    cb(null, true);
  },
}).single("file");

function receive(req: Request, res: Response): Promise<void> {
  return new Promise((resolve, reject) => {
    upload(req, res, (err: unknown) => {
      if (!err) return resolve();
      if (err instanceof multer.MulterError) {
        if (err.code === "LIMIT_FILE_SIZE") return reject(new AppError(413, "payload_too_large", "File is too large."));
        return reject(new AppError(400, "bad_request", err.message));
      }
      reject(err);
    });
  });
}

/** Multipart framing (boundaries, headers, small fields) on top of the file bytes. */
const MULTIPART_SLACK = 64 * 1024;
const fmtMb =(n: number) => `${Math.round(n / 1024 / 1024)} MB`;

filesRouter.post("/", async (req, res) => {
  db();
  if (!req.is("multipart/form-data")) throw new AppError(400, "bad_request", "Expected multipart/form-data with a `file` field");
  // Refuse early on the declared size, before multer buffers the body in memory.
  const declared = Number(req.headers["content-length"]);
  if (Number.isFinite(declared) && declared > 0) {
    if (declared > MAX_UPLOAD_BYTES + MULTIPART_SLACK) throw new AppError(413, "payload_too_large", "File is too large.");
    await checkUpload(userOf(req), Math.max(0, declared - MULTIPART_SLACK));
  }
  await receive(req, res);
  const f = req.file;
  if (!f) throw new AppError(400, "bad_request", "Missing `file` field");
  const name = fixName(f.originalname);
  const cls = classify(name, f.mimetype);
  if (!cls) throw new AppError(415, "unsupported_media_type", "Unsupported file type");
  if (f.size > SIZE_LIMITS[cls.kind]) {
    throw new AppError(413, "payload_too_large", `${cls.kind[0].toUpperCase()}${cls.kind.slice(1)} files can be at most ${fmtMb(SIZE_LIMITS[cls.kind])}.`);
  }
  if (f.size === 0) throw new AppError(400, "bad_request", "File is empty");
  const conversationId = typeof req.body?.conversationId === "string" && req.body.conversationId ? req.body.conversationId : null;
  if (conversationId && !UUID_RE.test(conversationId)) throw new AppError(400, "bad_request", "conversationId must be a UUID");
  const user = userOf(req);
  await checkUpload(user, f.size);

  // Storage refuses objects over its limit (Supabase Free: 50 MiB): such videos are re-encoded to fit while processing.
  const transcode = f.size > config.s3.maxObjectBytes;
  if (transcode && cls.kind !== "video") {
    throw new AppError(413, "payload_too_large", `Files can be at most ${fmtMb(config.s3.maxObjectBytes)}.`);
  }
  const id = randomUUID();
  const ext = transcode ? "mp4" : name.includes(".") ? name.split(".").pop()!.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 8) : "";
  const key = `${id}/original${ext ? "." + ext : ""}`;
  if (!transcode) {
    try {
      await putObject(key, f.buffer, cls.mime);
    } catch (e) {
      const msg = (e as Error).message ?? "";
      if (/maximum allowed size|EntityTooLarge|too large/i.test(msg)) {
        throw new AppError(413, "payload_too_large", `Files can be at most ${fmtMb(config.s3.maxObjectBytes)}.`);
      }
      log.warn("file store failed", { kind: cls.kind, size: f.size, message: msg.slice(0, 160) });
      throw new AppError(503, "unavailable", "File storage is unavailable, try again shortly.", true);
    }
  }
  const created = await db().storedFile.create({
    data: { id, conversationId: conversationId?.toLowerCase() ?? null, name, mime: transcode ? "video/mp4" : cls.mime, size: f.size, kind: cls.kind, s3Key: key, userId: user.id },
    select: INFO_SELECT,
  });
  await recordUpload(user, f.size);
  const target = { id, name, kind: cls.kind, s3Key: key, transcode };
  const done = processFile(target, f.buffer);
  // Images are quick: answer with the finished state.
  if (cls.kind === "image") await Promise.race([done, new Promise((r) => setTimeout(r, 4000))]);
  const row = (await getFileRow(id)) ?? toFileRow(created);
  log.info("file uploaded", { id, kind: cls.kind, size: f.size, ...(transcode ? { transcode } : {}) });
  res.status(201).json({ file: await signedInfo(row) });
});

// ---- storage manager ---------------------------------------------------

/** The caller's files, newest first by default: `?kind=&q=&sort=newest|largest|name&cursor=&limit=`. */
filesRouter.get("/", async (req, res) => {
  db();
  const query = parseListQuery(req.query as Record<string, unknown>);
  res.json(await listFiles(userOf(req).id, query));
});

/** Stored bytes and counts per kind against the account limits, plus today's uploads. */
filesRouter.get("/usage", async (req, res) => {
  db();
  const user = userOf(req);
  const [byKind, used, limits] = await Promise.all([usageByKind(user.id), usageFor(user.id), limitsFor(user)]);
  const kinds = Object.values(byKind);
  res.json({
    totalBytes: kinds.reduce((n, k) => n + k.bytes, 0),
    count: kinds.reduce((n, k) => n + k.count, 0),
    byKind,
    limits: { storageBytes: limits?.storageBytes ?? null, uploadsPerDay: limits?.uploads ?? null },
    today: { uploads: used.uploads, bytes: used.bytes },
    resetsAt: resetsAt(),
  });
});

const bulkSchema = z.object({ ids: z.array(z.string().regex(UUID_RE, "must be a file id")).min(1).max(200) });

/** Deletes several of the caller's files; unknown ids are reported, not an error. */
filesRouter.post("/bulk-delete", async (req, res) => {
  db();
  const parsed = bulkSchema.safeParse(req.body);
  if (!parsed.success) throw new AppError(400, "bad_request", parsed.error.issues[0]?.message ?? "ids must be file ids");
  const ids = [...new Set(parsed.data.ids.map((i) => i.toLowerCase()))];
  const missing: string[] = [];
  let deleted = 0;
  const limit = pLimit(4);
  await Promise.all(
    ids.map((id) =>
      limit(async () => {
        const row = await getFileRow(id);
        if (!row) return void missing.push(id);
        await deleteFile(row);
        deleted++;
      }),
    ),
  );
  res.json({ deleted, missing });
});

function fileId(raw: string): string {
  if (!UUID_RE.test(raw)) throw new AppError(404, "not_found", "File not found");
  return raw.toLowerCase();
}

filesRouter.get("/:id", async (req, res) => {
  db();
  const row = await getFileRow(fileId(req.params.id));
  if (!row) throw new AppError(404, "not_found", "File not found");
  res.json({ file: await signedInfo(row) });
});

filesRouter.get("/:id/text", async (req, res) => {
  db();
  const raw = Number(req.query.limit ?? 200_000);
  const limit = Number.isFinite(raw) ? Math.min(Math.max(Math.floor(raw), 1), 1_000_000) : 200_000;
  const row = await getFileRow(fileId(req.params.id), true);
  if (!row) throw new AppError(404, "not_found", "File not found");
  const text = row.text ?? "";
  if (row.status !== "ready" || !text) throw new AppError(404, "not_found", "No text available yet");
  res.json({ text: text.slice(0, limit), truncated: text.length > limit, chars: text.length });
});

filesRouter.delete("/:id", async (req, res) => {
  db();
  const row = await getFileRow(fileId(req.params.id));
  if (!row) throw new AppError(404, "not_found", "File not found");
  await deleteFile(row);
  res.status(204).end();
});

/** Renames a file (`{ name }`); the extension is kept and saved chats show the new name. */
filesRouter.patch("/:id", async (req, res) => {
  db();
  const row = await getFileRow(fileId(req.params.id));
  if (!row) throw new AppError(404, "not_found", "File not found");
  const name = cleanRename(req.body?.name, row.name);
  if (name !== row.name) {
    await db().storedFile.update({ where: { id: row.id }, data: { name } });
    await markAttachments(row.id, { name });
  }
  res.json({ file: await signedInfo({ ...row, name }) });
});
