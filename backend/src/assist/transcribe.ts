import { Router, type Request, type Response } from "express";
import multer from "multer";
import { config } from "../config.js";
import { withTelemetry } from "../db/usage.js";
import { groqTranscribe } from "../files/media.js";
import { AppError } from "../util/errors.js";

/** About two minutes of m4a/opus voice is well under this. */
export const MAX_VOICE_BYTES = 4 * 1024 * 1024;
const MULTIPART_SLACK = 16 * 1024;
const AUDIO_EXT = /\.(m4a|mp4|aac|ogg|oga|opus|webm|wav|mp3|flac)$/i;
const LANG_RE = /^[a-z]{2,3}(?:[-_][A-Za-z]{2,4})?$/;

export function isAudio(mime: string, name: string): boolean {
  const m = mime.toLowerCase();
  if (m.startsWith("audio/")) return true;
  return (m === "video/mp4" || m === "application/octet-stream") && AUDIO_EXT.test(name);
}

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_VOICE_BYTES, files: 1, fields: 4, parts: 6 },
  fileFilter: (_req, file, cb) => {
    if (!isAudio(file.mimetype, file.originalname)) return cb(new AppError(415, "unsupported_media_type", "Only audio can be transcribed."));
    cb(null, true);
  },
}).single("file");

function receive(req: Request, res: Response): Promise<void> {
  return new Promise((resolve, reject) => {
    upload(req, res, (err: unknown) => {
      if (!err) return resolve();
      if (err instanceof multer.MulterError) {
        if (err.code === "LIMIT_FILE_SIZE") return reject(new AppError(413, "payload_too_large", "Recording is too long."));
        return reject(new AppError(400, "bad_request", err.message));
      }
      reject(err);
    });
  });
}

/** "en-IN" / "hi_IN" / "hi" to the ISO-639-1 code Whisper takes; undefined means auto-detect. */
export function languageHint(raw: unknown): string | undefined {
  if (typeof raw !== "string" || !LANG_RE.test(raw.trim())) return undefined;
  return raw.trim().slice(0, 2).toLowerCase();
}

export const transcribeRouter = Router();

transcribeRouter.post("/transcribe", async (req, res) => {
  if (!req.is("multipart/form-data")) throw new AppError(400, "bad_request", "Expected multipart/form-data with a `file` field");
  const declared = Number(req.headers["content-length"]);
  if (Number.isFinite(declared) && declared > MAX_VOICE_BYTES + MULTIPART_SLACK) throw new AppError(413, "payload_too_large", "Recording is too long.");
  await receive(req, res);
  const f = req.file;
  if (!f || f.size === 0) throw new AppError(400, "bad_request", "Missing `file` field");
  if (!config.groqApiKey) throw new AppError(503, "unavailable", "Transcription is not configured.", true);
  try {
    const out = await withTelemetry({ purpose: "transcribe" }, () =>
      groqTranscribe(f.buffer, f.originalname || "voice.m4a", {
        mime: f.mimetype.startsWith("audio/") ? f.mimetype : "audio/mp4",
        language: languageHint(req.body?.language),
      }),
    );
    res.json(out);
  } catch {
    throw new AppError(502, "upstream_error", "Transcription failed, try again.", true);
  }
});
