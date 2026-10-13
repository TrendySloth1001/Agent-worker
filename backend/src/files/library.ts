import { userCrypto } from "../crypto/userData.js";
import { fuzzyScore, needsFuzzy } from "../nlp/text.js";
import { db, Prisma } from "../db/prisma.js";
import { AppError } from "../util/errors.js";
import type { FileKind } from "./kinds.js";
import { INFO_SELECT, signedInfo, toFileRow, type FileInfo } from "./store.js";

/** The storage manager's view of the user's files (GET /files). */

export const LIST_SORTS = ["newest", "largest", "name"] as const;
export type ListSort = (typeof LIST_SORTS)[number];
const KINDS: FileKind[] = ["image", "document", "video", "audio"];
export const LIST_MAX = 100;
const LIST_DEFAULT = 40;

export type ListQuery = { kind: FileKind | null; q: string; sort: ListSort; cursor: Cursor | null; limit: number };

/** Keyset position: the sort value and id of the last row of the previous page. */
export type Cursor = { v: string | number; id: string };

export function encodeCursor(c: Cursor): string {
  return Buffer.from(JSON.stringify(c)).toString("base64url");
}

export function decodeCursor(raw: string, sort: ListSort): Cursor {
  try {
    const c = JSON.parse(Buffer.from(raw, "base64url").toString("utf8")) as Partial<Cursor>;
    const okV = sort === "largest" ? typeof c.v === "number" && Number.isFinite(c.v) : typeof c.v === "string";
    if (okV && typeof c.id === "string" && /^[0-9a-f-]{36}$/i.test(c.id)) return { v: c.v!, id: c.id };
  } catch {
    /* falls through */
  }
  throw new AppError(400, "bad_request", "Invalid cursor");
}

const str = (v: unknown) => (typeof v === "string" ? v : Array.isArray(v) && typeof v[0] === "string" ? v[0] : "");

/** Validates `?kind=&q=&sort=&cursor=&limit=` (kind also takes plurals: images, videos, documents). */
export function parseListQuery(query: Record<string, unknown>): ListQuery {
  const rawKind = str(query.kind).toLowerCase().replace(/s$/, "");
  let kind: FileKind | null = null;
  if (rawKind && rawKind !== "all") {
    if (!KINDS.includes(rawKind as FileKind)) throw new AppError(400, "bad_request", "kind must be one of image, video, audio, document");
    kind = rawKind as FileKind;
  }
  const rawSort = str(query.sort).toLowerCase() || "newest";
  if (!LIST_SORTS.includes(rawSort as ListSort)) throw new AppError(400, "bad_request", "sort must be newest, largest or name");
  const sort = rawSort as ListSort;
  const n = Number(str(query.limit) || LIST_DEFAULT);
  const limit = Number.isFinite(n) ? Math.min(Math.max(Math.floor(n), 1), LIST_MAX) : LIST_DEFAULT;
  const rawCursor = str(query.cursor);
  return { kind, q: str(query.q).trim().slice(0, 100), sort, cursor: rawCursor ? decodeCursor(rawCursor, sort) : null, limit };
}

/** Prisma order and "after the cursor" filter for a sort. Ties break on id. */
export function sortPlan(sort: ListSort, cursor: Cursor | null): { orderBy: Prisma.StoredFileOrderByWithRelationInput[]; after: Prisma.StoredFileWhereInput | null } {
  switch (sort) {
    case "largest":
      return {
        orderBy: [{ size: "desc" }, { id: "desc" }],
        after: cursor ? { OR: [{ size: { lt: BigInt(cursor.v) } }, { size: BigInt(cursor.v), id: { lt: cursor.id } }] } : null,
      };
    case "name":
      return {
        orderBy: [{ name: "asc" }, { id: "asc" }],
        after: cursor ? { OR: [{ name: { gt: String(cursor.v) } }, { name: String(cursor.v), id: { gt: cursor.id } }] } : null,
      };
    default: {
      const at = cursor ? new Date(String(cursor.v)) : null;
      return {
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
        after: at ? { OR: [{ createdAt: { lt: at } }, { createdAt: at, id: { lt: cursor!.id } }] } : null,
      };
    }
  }
}

export type LibraryFile = FileInfo & { conversation: { id: string; title: string | null } | null };

/** Conversations (newest first) whose saved messages attach each file id. */
async function conversationsOf(userId: string | null, ids: string[]): Promise<Map<string, { id: string; title: string | null }>> {
  if (ids.length === 0) return new Map();
  // Raw: jsonb containment per file id over message attachments has no Prisma filter.
  const rows = await db().$queryRaw<Array<{ file_id: string; id: string; title: string | null }>>`
    SELECT DISTINCT ON (f.fid) f.fid AS file_id, c.id::text AS id, c.title
      FROM unnest(${ids}::text[]) AS f(fid)
      JOIN conversation_messages m ON m.attachments @> jsonb_build_array(jsonb_build_object('id', f.fid))
      JOIN conversations c ON c.id = m.conversation_id
     WHERE c.user_id IS NOT DISTINCT FROM ${userId}::uuid
     ORDER BY f.fid, c.updated_at DESC`;
  return new Map(rows.map((r) => [r.file_id, { id: r.id, title: r.title }]));
}

export async function listFiles(userId: string | null, q: ListQuery): Promise<{ files: LibraryFile[]; nextCursor: string | null }> {
  const plan = sortPlan(q.sort, q.cursor);
  const where: Prisma.StoredFileWhereInput = {
    userId,
    ...(q.kind ? { kind: q.kind } : {}),
    ...(q.q ? { name: { contains: q.q, mode: "insensitive" } } : {}),
    ...(plan.after ? { AND: [plan.after] } : {}),
  };
  let found = await db().storedFile.findMany({ where, orderBy: plan.orderBy, take: q.limit + 1, select: INFO_SELECT });
  // Few substring hits on the first page: retry with typo / stem / synonym tolerant name matching.
  if (q.q && !q.cursor && needsFuzzy(found.length)) {
    const names = await db().storedFile.findMany({ where: { userId, ...(q.kind ? { kind: q.kind } : {}) }, select: { id: true, name: true }, take: 2000 });
    const ids = names.filter((n) => fuzzyScore(q.q, n.name) >= 0.7).map((n) => n.id);
    if (ids.length > found.length) {
      found = await db().storedFile.findMany({ where: { ...where, name: undefined, id: { in: ids } }, orderBy: plan.orderBy, take: q.limit + 1, select: INFO_SELECT });
    }
  }
  const rows = found.map(toFileRow);
  const page = rows.slice(0, q.limit);
  const convs = await conversationsOf(userId, page.map((r) => r.id));
  // Titles of chats a file was uploaded into but never saved with (files.conversation_id).
  const loose = page.filter((r) => !convs.has(r.id) && r.conversationId).map((r) => r.conversationId!);
  const extra = loose.length
    ? await db().conversation.findMany({ where: { id: { in: [...new Set(loose)] }, userId }, select: { id: true, title: true } })
    : [];
  const byId = new Map(extra.map((c) => [c.id, c]));
  const crypto = await userCrypto(userId);
  const files = await Promise.all(
    page.map(async (r) => {
      const info = await signedInfo(r);
      const conv = convs.get(r.id) ?? (r.conversationId ? byId.get(r.conversationId) ?? null : null);
      return { ...info, conversation: conv ? { id: conv.id, title: conv.title ? crypto.open("conversations", "title", conv.title) : null } : null };
    }),
  );
  const last = page[page.length - 1];
  const nextCursor =
    rows.length > q.limit && last
      ? encodeCursor({ v: q.sort === "largest" ? last.size : q.sort === "name" ? last.name : last.createdAt.toISOString(), id: last.id })
      : null;
  return { files, nextCursor };
}

export type KindUsage = { count: number; bytes: number };

/** Totals per kind for one user (every kind present, zero when none). */
export async function usageByKind(userId: string | null): Promise<Record<FileKind, KindUsage>> {
  const groups = await db().storedFile.groupBy({ by: ["kind"], where: { userId }, _count: { _all: true }, _sum: { size: true } });
  const out = Object.fromEntries(KINDS.map((k) => [k, { count: 0, bytes: 0 }])) as Record<FileKind, KindUsage>;
  for (const g of groups) {
    if (KINDS.includes(g.kind as FileKind)) out[g.kind as FileKind] = { count: g._count._all, bytes: Number(g._sum.size ?? 0) };
  }
  return out;
}

/** A display name for a renamed file: trimmed, no path parts or control characters, original extension kept. */
export function cleanRename(raw: unknown, current: string): string {
  if (typeof raw !== "string") throw new AppError(400, "bad_request", "name must be a string");
  let name = raw.split(/[\\/]/).pop()!.replace(/[\u0000-\u001f]/g, "").trim();
  if (!name || name === "." || name === "..") throw new AppError(400, "bad_request", "name must not be empty");
  const ext = current.includes(".") ? current.slice(current.lastIndexOf(".")) : "";
  if (ext && !name.toLowerCase().endsWith(ext.toLowerCase())) name = `${name}${ext}`;
  if (name.length > 200) name = `${name.slice(0, 200 - ext.length)}${ext}`;
  return name;
}
