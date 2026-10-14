import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
  ListObjectsV2Command,
  CreateMultipartUploadCommand,
  UploadPartCommand,
  CompleteMultipartUploadCommand,
  AbortMultipartUploadCommand,
  CopyObjectCommand,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { config } from "../config.js";
import { AppError } from "../util/errors.js";
import { isSealedObject, userCrypto } from "../crypto/userData.js";

let client: S3Client | null = null;

function s3(): S3Client {
  const c = config.s3;
  if (!c.endpoint || !c.accessKeyId || !c.secretAccessKey) throw new AppError(503, "unavailable", "File uploads aren't available right now.", true);
  client ??= new S3Client({
    endpoint: c.endpoint,
    region: c.region,
    forcePathStyle: true,
    credentials: { accessKeyId: c.accessKeyId, secretAccessKey: c.secretAccessKey },
  });
  return client;
}

export async function putObject(key: string, body: Buffer, contentType: string): Promise<void> {
  await s3().send(new PutObjectCommand({ Bucket: config.s3.bucket, Key: key, Body: body, ContentType: contentType }));
}

export async function getObject(key: string): Promise<Buffer> {
  const res = await s3().send(new GetObjectCommand({ Bucket: config.s3.bucket, Key: key }));
  if (!res.Body) throw new Error("empty object");
  return Buffer.from(await res.Body.transformToByteArray());
}

/**
 * User uploads are encrypted before they leave the process: the body is `SPKYENC1 | iv | tag | ciphertext`
 * (AES-256-GCM, the owner's data key, AAD = object key + user). Objects written before encryption have no
 * marker and are returned as they are. Shared files (app releases) keep using putObject/presign.
 */
export const OBJECT_OVERHEAD = 8 + 12 + 16;

/** The raw object calls behind putUserObject/getUserObject (replaced in tests). */
export const io: { put: typeof putObject; get: typeof getObject } = { put: (k, b, t) => putObject(k, b, t), get: (k) => getObject(k) };

export async function putUserObject(userId: string | null, key: string, body: Buffer, contentType: string): Promise<void> {
  const c = await userCrypto(userId);
  await io.put(key, c.sealBytes(key, body), contentType);
}

export async function getUserObject(userId: string | null, key: string): Promise<Buffer> {
  const raw = await io.get(key);
  if (!isSealedObject(raw)) return raw; // legacy plaintext object
  if (!userId) throw new AppError(500, "decrypt_failed", "Some saved data couldn't be read. Try again shortly.");
  return (await userCrypto(userId)).openBytes(key, raw);
}

export async function deleteObject(key: string): Promise<void> {
  await s3().send(new DeleteObjectCommand({ Bucket: config.s3.bucket, Key: key }));
}

/** Every key under [prefix] (a file's objects live under `<id>/`). */
export async function listKeys(prefix: string): Promise<string[]> {
  const keys: string[] = [];
  let token: string | undefined;
  do {
    const res = await s3().send(new ListObjectsV2Command({ Bucket: config.s3.bucket, Prefix: prefix, ContinuationToken: token }));
    for (const o of res.Contents ?? []) if (o.Key) keys.push(o.Key);
    token = res.IsTruncated ? res.NextContinuationToken : undefined;
  } while (token);
  return keys;
}

/** Part size for streamed uploads (S3's minimum is 5 MiB; peak memory is about one part). */
export const UPLOAD_PART_BYTES = 8 * 1024 * 1024;

/** The S3 calls behind [putStream] (replaced in tests). */
export type MultipartIo = {
  create(key: string, contentType: string): Promise<string>;
  part(key: string, uploadId: string, n: number, body: Buffer): Promise<string>;
  complete(key: string, uploadId: string, parts: Array<{ n: number; etag: string }>): Promise<void>;
  abort(key: string, uploadId: string): Promise<void>;
  put(key: string, body: Buffer, contentType: string): Promise<void>;
};

export const multipartIo: MultipartIo = {
  async create(key, contentType) {
    const r = await s3().send(new CreateMultipartUploadCommand({ Bucket: config.s3.bucket, Key: key, ContentType: contentType }));
    if (!r.UploadId) throw new Error("no upload id");
    return r.UploadId;
  },
  async part(key, uploadId, n, body) {
    const r = await s3().send(new UploadPartCommand({ Bucket: config.s3.bucket, Key: key, UploadId: uploadId, PartNumber: n, Body: body }));
    if (!r.ETag) throw new Error("no etag");
    return r.ETag;
  },
  async complete(key, uploadId, parts) {
    await s3().send(
      new CompleteMultipartUploadCommand({
        Bucket: config.s3.bucket,
        Key: key,
        UploadId: uploadId,
        MultipartUpload: { Parts: parts.map((p) => ({ PartNumber: p.n, ETag: p.etag })) },
      }),
    );
  },
  async abort(key, uploadId) {
    await s3().send(new AbortMultipartUploadCommand({ Bucket: config.s3.bucket, Key: key, UploadId: uploadId }));
  },
  put: (k, b, t) => putObject(k, b, t),
};

/**
 * Streams [source] into S3 without holding it in memory: parts of [partBytes] go up as they fill (a body
 * smaller than one part is a single PUT). [onChunk] sees every byte once (hashing). Aborts the multipart
 * upload on any error. Returns the byte count.
 */
export async function putStream(
  key: string,
  source: AsyncIterable<Buffer | Uint8Array>,
  contentType: string,
  opts: { partBytes?: number; onChunk?: (c: Buffer) => void; io?: MultipartIo } = {},
): Promise<number> {
  const io = opts.io ?? multipartIo;
  const partBytes = opts.partBytes ?? UPLOAD_PART_BYTES;
  let uploadId: string | null = null;
  const parts: Array<{ n: number; etag: string }> = [];
  let pending: Buffer[] = [];
  let pendingLen = 0;
  let total = 0;
  const flush = async (len: number) => {
    const all = pending.length === 1 ? pending[0] : Buffer.concat(pending);
    const body = all.subarray(0, len);
    const rest = all.subarray(len);
    pending = rest.length ? [rest] : [];
    pendingLen = rest.length;
    uploadId ??= await io.create(key, contentType);
    const n = parts.length + 1;
    parts.push({ n, etag: await io.part(key, uploadId, n, body) });
  };
  try {
    for await (const c of source) {
      const chunk = Buffer.isBuffer(c) ? c : Buffer.from(c);
      opts.onChunk?.(chunk);
      total += chunk.length;
      pending.push(chunk);
      pendingLen += chunk.length;
      while (pendingLen >= partBytes) await flush(partBytes);
    }
    if (!uploadId) {
      await io.put(key, Buffer.concat(pending), contentType);
      return total;
    }
    if (pendingLen > 0) await flush(pendingLen);
    await io.complete(key, uploadId, parts);
    return total;
  } catch (e) {
    if (uploadId) await io.abort(key, uploadId).catch(() => undefined);
    throw e;
  }
}

/** Server-side copy inside the bucket. */
export async function copyObject(from: string, to: string): Promise<void> {
  const b = config.s3.bucket;
  await s3().send(new CopyObjectCommand({ Bucket: b, Key: to, CopySource: `${b}/${from.split("/").map(encodeURIComponent).join("/")}` }));
}

/** [length] bytes from [offset] (a ranged GET). */
export async function getRange(key: string, offset: number, length: number): Promise<Buffer> {
  if (length <= 0) return Buffer.alloc(0);
  const res = await s3().send(new GetObjectCommand({ Bucket: config.s3.bucket, Key: key, Range: `bytes=${offset}-${offset + length - 1}` }));
  if (!res.Body) throw new Error("empty object");
  return Buffer.from(await res.Body.transformToByteArray());
}

export async function presign(key: string, expiresIn = 3600): Promise<string> {
  return getSignedUrl(s3(), new GetObjectCommand({ Bucket: config.s3.bucket, Key: key }), { expiresIn });
}
