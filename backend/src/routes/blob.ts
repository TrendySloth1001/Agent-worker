import { Router } from "express";
import { db } from "../db/prisma.js";
import { verifyBlob } from "../files/blobUrl.js";
import { getUserObject } from "../storage/s3.js";
import { AppError } from "../util/errors.js";

/**
 * GET /files/blob/:id/:variant?exp=&sig= : a file's decrypted bytes, for the signed links in file listings.
 * Public (the signature is the credential, like the storage links it replaces); mounted before requireUser.
 */
export const blobRouter = Router();

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Types the app shows inline; everything else downloads, so an uploaded page can never run on the API origin. */
const INLINE = /^(image\/(png|jpe?g|gif|webp|heic|heif|bmp)|video\/|audio\/)/i;

blobRouter.get("/:id/:variant", async (req, res) => {
  const id = req.params.id.toLowerCase();
  if (!UUID_RE.test(id) || !verifyBlob(id, req.params.variant, req.query.exp, req.query.sig)) throw new AppError(404, "not_found", "File not found");
  const thumb = req.params.variant === "thumb";
  const row = await db().storedFile.findUnique({ where: { id }, select: { userId: true, s3Key: true, thumbKey: true, mime: true, name: true } });
  const key = row ? (thumb ? row.thumbKey : row.s3Key) : null;
  if (!row || !key) throw new AppError(404, "not_found", "File not found");
  const body = await getUserObject(row.userId, key).catch((e) => {
    if (e instanceof AppError) throw e;
    throw new AppError(404, "not_found", "File not found");
  });

  const type = thumb ? "image/jpeg" : row.mime || "application/octet-stream";
  res.setHeader("Content-Type", type);
  res.setHeader("Accept-Ranges", "bytes");
  res.setHeader("Cache-Control", "private, max-age=300");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Content-Security-Policy", "default-src 'none'; sandbox");
  res.setHeader("Content-Disposition", `${thumb || INLINE.test(type) ? "inline" : "attachment"}; filename*=UTF-8''${encodeURIComponent(row.name)}`);

  const m = /^bytes=(\d*)-(\d*)$/.exec(String(req.headers.range ?? ""));
  if (m && (m[1] || m[2])) {
    const size = body.length;
    let start = m[1] ? Number(m[1]) : Math.max(size - Number(m[2]), 0);
    let end = m[1] && m[2] ? Number(m[2]) : size - 1;
    end = Math.min(end, size - 1);
    if (start > end || start >= size) {
      res.status(416).setHeader("Content-Range", `bytes */${size}`).end();
      return;
    }
    start = Math.max(start, 0);
    res.status(206).setHeader("Content-Range", `bytes ${start}-${end}/${size}`).setHeader("Content-Length", String(end - start + 1)).end(body.subarray(start, end + 1));
    return;
  }
  res.setHeader("Content-Length", String(body.length));
  res.end(body);
});
