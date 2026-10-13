import { unindex } from "../ingest/indexer.js";
import { db, type Prisma } from "../db/prisma.js";
import { ownerFilter } from "../auth/context.js";
import { deleteObject, listKeys } from "../storage/s3.js";
import { userCrypto } from "../crypto/userData.js";
import { blobUrl } from "./blobUrl.js";
import { log } from "../util/logger.js";
import { config } from "../config.js";
import type { FileKind } from "./kinds.js";
import { USER_MSG, userSafe } from "../util/userMessages.js";

export type FileRow = {
  id: string;
  conversationId: string | null;
  name: string;
  mime: string;
  size: number;
  kind: FileKind;
  status: "processing" | "ready" | "failed";
  error: string | null;
  s3Key: string;
  thumbKey: string | null;
  meta: Record<string, any>;
  text?: string | null;
  createdAt: Date;
  /** Owner: whose data key seals the stored text and the objects. */
  userId?: string | null;
};

export type FileInfo = {
  id: string;
  name: string;
  mime: string;
  size: number;
  kind: FileKind;
  status: FileRow["status"];
  error: string | null;
  url?: string;
  thumbUrl?: string | null;
  meta: Record<string, unknown>;
  createdAt: string;
};

const META_PUBLIC = ["width", "height", "pages", "chars", "durationS", "frames", "hasTranscript"];

/** Columns of a FileRow (everything but the extracted text and the owner). */
export const INFO_SELECT = {
  id: true,
  conversationId: true,
  name: true,
  mime: true,
  size: true,
  kind: true,
  status: true,
  error: true,
  s3Key: true,
  thumbKey: true,
  meta: true,
  createdAt: true,
  userId: true,
} satisfies Prisma.StoredFileSelect;

type Selected = Prisma.StoredFileGetPayload<{ select: typeof INFO_SELECT }> & { text?: string | null };

/** A selected files row as FileRow (bigint size as number, JSON meta as an object). */
export function toFileRow(r: Selected): FileRow {
  const meta = r.meta && typeof r.meta === "object" && !Array.isArray(r.meta) ? (r.meta as Record<string, any>) : {};
  return {
    ...r,
    size: Number(r.size),
    kind: r.kind as FileKind,
    status: r.status as FileRow["status"],
    meta,
  };
}

/** FileInfo without signed URLs (what conversations persist). */
export function plainInfo(r: FileRow): FileInfo {
  const meta: Record<string, unknown> = {};
  for (const k of META_PUBLIC) if (r.meta?.[k] !== undefined) meta[k] = r.meta[k];
  return {
    id: r.id,
    name: r.name,
    mime: r.mime,
    size: Number(r.size),
    kind: r.kind,
    status: r.status,
    error: userSafe(r.error, USER_MSG.fileFailed),
    meta,
    createdAt: r.createdAt.toISOString(),
  };
}

export async function signedInfo(r: FileRow): Promise<FileInfo> {
  // A video too big for storage is only stored once it is re-encoded; until
  // then its key names nothing, so no link is handed out (players would 404).
  const pending = r.status === "processing" && r.size > config.s3.maxObjectBytes;
  // Objects are encrypted, so a storage link would hand out ciphertext: links point at the API, which decrypts (src/routes/blob.ts).
  return { ...plainInfo(r), url: pending ? undefined : blobUrl(r.id, "original"), thumbUrl: r.thumbKey ? blobUrl(r.id, "thumb") : null };
}

/** A file of the current request's user (any file outside a request). */
export async function getFileRow(id: string, withText = false): Promise<FileRow | null> {
  const [unscoped, uid] = ownerFilter();
  const row = await db().storedFile.findFirst({
    where: { id, ...(unscoped ? {} : { userId: uid }) },
    select: { ...INFO_SELECT, text: withText },
  });
  if (!row) return null;
  // The extracted text is sealed at rest.
  if (withText && row.text) row.text = (await userCrypto(row.userId)).open("files", "text", row.text);
  return toFileRow(row);
}

/** Storage keys a file row names (original, thumbnail, video frames). */
export function knownKeys(row: Pick<FileRow, "s3Key" | "thumbKey" | "meta">): string[] {
  const frames = Array.isArray(row.meta?.frameKeys) ? (row.meta.frameKeys as unknown[]).filter((k): k is string => typeof k === "string") : [];
  return [...new Set([row.s3Key, row.thumbKey, ...frames].filter((k): k is string => !!k))];
}

/**
 * Removes a file's objects and its rows. Objects are found by the row and by
 * listing `<id>/` (catches frames or thumbnails a failed run left behind).
 * Saved messages keep the attachment as a "deleted" placeholder.
 */
export async function deleteFile(row: FileRow): Promise<void> {
  const listed = await listKeys(`${row.id}/`).catch((e) => {
    log.warn("file object listing failed", { id: row.id, message: (e as Error).message.slice(0, 120) });
    return [] as string[];
  });
  const keys = [...new Set([...knownKeys(row), ...listed])];
  await Promise.allSettled(keys.map((k) => deleteObject(k)));
  await db().storedFile.deleteMany({ where: { id: row.id } });
  void unindex("file", row.id);
  await markAttachments(row.id, { deleted: true, status: "deleted" }).catch((e) => {
    log.warn("attachment placeholder update failed", { id: row.id, message: (e as Error).message.slice(0, 120) });
  });
}

/**
 * Merges [patch] into every saved attachment object with this file id, in
 * the current user's conversations (e.g. `{deleted: true}` or a new name).
 */
export async function markAttachments(fileId: string, patch: Record<string, unknown>): Promise<number> {
  const [unscoped, uid] = ownerFilter();
  const json = JSON.stringify(patch);
  // Raw: rewriting matching elements of a jsonb array has no Prisma equivalent.
  return db().$executeRaw`
    UPDATE conversation_messages m SET attachments = (
      SELECT COALESCE(jsonb_agg(CASE WHEN e->>'id' = ${fileId}::text THEN e || ${json}::jsonb ELSE e END ORDER BY i), '[]'::jsonb)
        FROM jsonb_array_elements(m.attachments) WITH ORDINALITY AS t(e, i))
      FROM conversations c
     WHERE c.id = m.conversation_id
       AND jsonb_typeof(m.attachments) = 'array'
       AND m.attachments @> jsonb_build_array(jsonb_build_object('id', ${fileId}::text))
       AND (${unscoped}::boolean OR c.user_id IS NOT DISTINCT FROM ${uid}::uuid)`;
}
