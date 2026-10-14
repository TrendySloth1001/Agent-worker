import { createHash, randomUUID } from "node:crypto";
import { AppError } from "../util/errors.js";
import { putStream, type MultipartIo } from "../storage/s3.js";
import { MAX_APK_BYTES } from "./logic.js";

export type StagedApk = { key: string; sha256: string; size: number };

/** Where an upload lives until the form fields (build/version) are known and checked. */
export const stagingKey = () => `releases/_incoming/${randomUUID()}.apk`;

/**
 * Streams an uploaded APK to [key] in S3 while computing its sha256 and size. Rejects (and aborts the
 * S3 upload) when the first bytes are not a zip signature ("PK") or the size cap is exceeded; an empty
 * body is a 400. Memory stays at about one upload part.
 */
export async function stageApk(
  source: AsyncIterable<Buffer | Uint8Array>,
  key: string,
  opts: { maxBytes?: number; partBytes?: number; io?: MultipartIo } = {},
): Promise<StagedApk> {
  const max = opts.maxBytes ?? MAX_APK_BYTES;
  const hash = createHash("sha256");
  let seen = 0;
  let head = Buffer.alloc(0);
  const size = await putStream(key, source, "application/vnd.android.package-archive", {
    partBytes: opts.partBytes,
    io: opts.io,
    onChunk: (c) => {
      if (head.length < 2) {
        head = Buffer.concat([head, c.subarray(0, 2 - head.length)]);
        if (head.length === 2 && (head[0] !== 0x50 || head[1] !== 0x4b)) throw new AppError(400, "bad_request", "That file is not an APK");
      }
      seen += c.length;
      if (seen > max) throw new AppError(413, "payload_too_large", "APK is too large (max 150 MB).");
      hash.update(c);
    },
  });
  if (size === 0) throw new AppError(400, "bad_request", "Missing apk file");
  if (head.length < 2) throw new AppError(400, "bad_request", "That file is not an APK");
  return { key, sha256: hash.digest("hex"), size };
}
