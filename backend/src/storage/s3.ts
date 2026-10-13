import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand, ListObjectsV2Command } from "@aws-sdk/client-s3";
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

export async function presign(key: string, expiresIn = 3600): Promise<string> {
  return getSignedUrl(s3(), new GetObjectCommand({ Bucket: config.s3.bucket, Key: key }), { expiresIn });
}
