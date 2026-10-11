import { randomUUID } from "node:crypto";
import { Router, type Request, type Response } from "express";
import multer from "multer";
import { getPool, query } from "../db/pool.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { classify, MAX_UPLOAD_BYTES, SIZE_LIMITS } from "../files/kinds.js";
import { deleteFile, getFileRow, signedInfo, type FileRow } from "../files/store.js";
import { processFile } from "../files/process.js";
import { deleteObject, putObject } from "../storage/s3.js";

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

const fmtMb = (n: number) => `${Math.round(n / 1024 / 1024)} MB`;

filesRouter.post("/", async (req, res) => {
  getPool();
  if (!req.is("multipart/form-data")) throw new AppError(400, "bad_request", "Expected multipart/form-data with a `file` field");
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

  const id = randomUUID();
  const ext = name.includes(".") ? name.split(".").pop()!.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 8) : "";
  const key = `${id}/original${ext ? "." + ext : ""}`;
  await putObject(key, f.buffer, cls.mime);
  const { rows } = await query<FileRow>(
    `INSERT INTO files (id, conversation_id, name, mime, size, kind, s3_key) VALUES ($1,$2,$3,$4,$5,$6,$7)
     RETURNING id, conversation_id, name, mime, size, kind, status, error, s3_key, thumb_key, meta, created_at`,
    [id, conversationId?.toLowerCase() ?? null, name, cls.mime, f.size, cls.kind, key],
  );
  const target = { id, name, kind: cls.kind, s3_key: key };
  const done = processFile(target, f.buffer);
  // Images are quick: answer with the finished state.
  if (cls.kind === "image") await Promise.race([done, new Promise((r) => setTimeout(r, 4000))]);
  const row = (await getFileRow(id)) ?? rows[0];
  log.info("file uploaded", { id, kind: cls.kind, size: f.size });
  res.status(201).json({ file: await signedInfo(row) });
});

function fileId(raw: string): string {
  if (!UUID_RE.test(raw)) throw new AppError(404, "not_found", "File not found");
  return raw.toLowerCase();
}

filesRouter.get("/:id", async (req, res) => {
  getPool();
  const row = await getFileRow(fileId(req.params.id));
  if (!row) throw new AppError(404, "not_found", "File not found");
  res.json({ file: await signedInfo(row) });
});

filesRouter.get("/:id/text", async (req, res) => {
  getPool();
  const raw = Number(req.query.limit ?? 200_000);
  const limit = Number.isFinite(raw) ? Math.min(Math.max(Math.floor(raw), 1), 1_000_000) : 200_000;
  const row = await getFileRow(fileId(req.params.id), true);
  if (!row) throw new AppError(404, "not_found", "File not found");
  const text = row.text ?? "";
  if (row.status !== "ready" || !text) throw new AppError(404, "not_found", "No text available yet");
  res.json({ text: text.slice(0, limit), truncated: text.length > limit, chars: text.length });
});

filesRouter.delete("/:id", async (req, res) => {
  getPool();
  const row = await getFileRow(fileId(req.params.id));
  if (!row) throw new AppError(404, "not_found", "File not found");
  await deleteFile(row);
  res.status(204).end();
});
