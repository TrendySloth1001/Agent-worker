import { createHmac, timingSafeEqual } from "node:crypto";
import { config } from "../config.js";
import { urlSigningKey } from "../crypto/userData.js";

/**
 * Short-lived signed links to a file's (decrypted) bytes, served by the API: stored objects are ciphertext, so
 * the storage provider's own links can no longer be handed to the app. The signature covers file id, variant
 * and expiry; it is derived from the server's DATA_KEY, so links die with a key change.
 */
export const BLOB_URL_TTL_S = 3600;
export type BlobVariant = "original" | "thumb";

const sign = (id: string, variant: BlobVariant, exp: number) => createHmac("sha256", urlSigningKey()).update(`${id}.${variant}.${exp}`).digest("hex");

export function blobUrl(id: string, variant: BlobVariant, now = Date.now()): string {
  const exp = Math.floor(now / 1000) + BLOB_URL_TTL_S;
  return `${config.publicBaseUrl}/files/blob/${id}/${variant}?exp=${exp}&sig=${sign(id, variant, exp)}`;
}

export function verifyBlob(id: string, variant: string, exp: unknown, sig: unknown, now = Date.now()): variant is BlobVariant {
  if (variant !== "original" && variant !== "thumb") return false;
  const e = Number(exp);
  if (!Number.isInteger(e) || e * 1000 < now || typeof sig !== "string" || !/^[0-9a-f]{64}$/.test(sig)) return false;
  return timingSafeEqual(Buffer.from(sign(id, variant, e), "hex"), Buffer.from(sig, "hex"));
}
