import { blobUrl } from "./blobUrl.js";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Attachments of a saved message as clients get them. Rows saved by older app/server versions can still
 * carry `url` / `thumbUrl` captured when the message was sent: storage links (now ciphertext) or signed
 * links that expired. Whatever is stored is dropped and, for an attachment that names a file id, replaced
 * by freshly signed links to the API (which decrypts). `thumbUrl` is only re-issued when the entry had
 * one (images and videos do; documents have no poster).
 */
export function withFreshUrls(list: unknown): Array<Record<string, unknown>> {
  if (!Array.isArray(list)) return [];
  return list.map((raw) => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return raw as Record<string, unknown>;
    const { url: _u, thumbUrl, ...rest } = raw as Record<string, unknown>;
    const id = typeof rest.id === "string" && UUID_RE.test(rest.id) ? rest.id.toLowerCase() : null;
    if (!id || rest.deleted === true || rest.status === "deleted") return rest;
    return { ...rest, url: blobUrl(id, "original"), ...(thumbUrl ? { thumbUrl: blobUrl(id, "thumb") } : {}) };
  });
}
