import { db, type Prisma } from "../db/prisma.js";
import { ownerFilter } from "../auth/context.js";
import { deleteObject, presign } from "../storage/s3.js";
import type { FileKind } from "./kinds.js";

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
    error: r.error,
    meta,
    createdAt: r.createdAt.toISOString(),
  };
}

export async function signedInfo(r: FileRow): Promise<FileInfo> {
  const [url, thumbUrl] = await Promise.all([presign(r.s3Key), r.thumbKey ? presign(r.thumbKey) : Promise.resolve(null)]);
  return { ...plainInfo(r), url, thumbUrl };
}

/** A file of the current request's user (any file outside a request). */
export async function getFileRow(id: string, withText = false): Promise<FileRow | null> {
  const [unscoped, uid] = ownerFilter();
  const row = await db().storedFile.findFirst({
    where: { id, ...(unscoped ? {} : { userId: uid }) },
    select: { ...INFO_SELECT, text: withText },
  });
  return row ? toFileRow(row) : null;
}

/** Removes a file's objects (original, thumbnail, video frames) and its rows. */
export async function deleteFile(row: FileRow): Promise<void> {
  const keys = [row.s3Key, row.thumbKey, ...((row.meta?.frameKeys as string[] | undefined) ?? [])].filter(
    (k): k is string => !!k,
  );
  await Promise.allSettled(keys.map((k) => deleteObject(k)));
  await db().storedFile.deleteMany({ where: { id: row.id } });
}
