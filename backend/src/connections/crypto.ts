import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import { config } from "../config.js";
import { AppError } from "../util/errors.js";

/**
 * AES-256-GCM for connection tokens at rest. Stored form:
 * `v1:<base64(iv[12] | tag[16] | ciphertext)>`. The key is CONNECTIONS_KEY,
 * 32 bytes given as base64 or 64 hex characters.
 */

const VERSION = "v1";
const IV_BYTES = 12;
const TAG_BYTES = 16;

export function parseKey(raw: string | undefined): Buffer | null {
  const v = raw?.trim();
  if (!v) return null;
  const buf = /^[0-9a-f]{64}$/i.test(v) ? Buffer.from(v, "hex") : Buffer.from(v, "base64");
  return buf.length === 32 ? buf : null;
}

let cachedKey: Buffer | null | undefined;
function serverKey(): Buffer {
  if (cachedKey === undefined) cachedKey = parseKey(config.connectionsKey);
  if (!cachedKey) throw new AppError(503, "connections_key_missing", "Connected apps aren't available right now.");
  return cachedKey;
}

export function encryptSecret(plain: string, key: Buffer = serverKey()): string {
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const ct = Buffer.concat([cipher.update(plain, "utf8"), cipher.final()]);
  return `${VERSION}:${Buffer.concat([iv, cipher.getAuthTag(), ct]).toString("base64")}`;
}

export function decryptSecret(stored: string, key: Buffer = serverKey()): string {
  const [version, body] = stored.split(":", 2);
  if (version !== VERSION || !body) throw new Error("Unknown secret format");
  const buf = Buffer.from(body, "base64");
  const iv = buf.subarray(0, IV_BYTES);
  const tag = buf.subarray(IV_BYTES, IV_BYTES + TAG_BYTES);
  const decipher = createDecipheriv("aes-256-gcm", key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(buf.subarray(IV_BYTES + TAG_BYTES)), decipher.final()]).toString("utf8");
}
