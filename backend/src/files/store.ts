import { query } from "../db/pool.js";
import { deleteObject, presign } from "../storage/s3.js";
import type { FileKind } from "./kinds.js";

export type FileRow = {
  id: string;
  conversation_id: string | null;
  name: string;
  mime: string;
  size: string | number;
  kind: FileKind;
  status: "processing" | "ready" | "failed";
  error: string | null;
  s3_key: string;
  thumb_key: string | null;
  meta: Record<string, any>;
  text?: string | null;
  created_at: Date;
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

export const INFO_COLS = "id, conversation_id, name, mime, size, kind, status, error, s3_key, thumb_key, meta, created_at";

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
    createdAt: r.created_at.toISOString(),
  };
}

export async function signedInfo(r: FileRow): Promise<FileInfo> {
  const [url, thumbUrl] = await Promise.all([presign(r.s3_key), r.thumb_key ? presign(r.thumb_key) : Promise.resolve(null)]);
  return { ...plainInfo(r), url, thumbUrl };
}

export async function getFileRow(id: string, withText = false): Promise<FileRow | null> {
  const { rows } = await query<FileRow>(`SELECT ${INFO_COLS}${withText ? ", text" : ""} FROM files WHERE id = $1`, [id]);
  return rows[0] ?? null;
}

/** Removes a file's objects (original, thumbnail, video frames) and its rows. */
export async function deleteFile(row: FileRow): Promise<void> {
  const keys = [row.s3_key, row.thumb_key, ...((row.meta?.frameKeys as string[] | undefined) ?? [])].filter(
    (k): k is string => !!k,
  );
  await Promise.allSettled(keys.map((k) => deleteObject(k)));
  await query("DELETE FROM files WHERE id = $1", [row.id]);
}
