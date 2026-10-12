import { db, tx } from "../db/prisma.js";
import { deleteFile, INFO_SELECT, toFileRow } from "../files/store.js";
import { cancelIndex } from "../recall/index.js";
import { log } from "../util/logger.js";

// `files.id::text` is lowercase, so only lowercase ids ever matched a row.
const FILE_ID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** Chats deleted per transaction (bounds the id lists in each query). */
export const DELETE_BATCH = 200;
/** Files whose storage objects are removed at the same time. */
const FILE_CONCURRENCY = 4;

/** Attachment ids named in saved messages: any attachment object with an id (as text, like `a->>'id'`). */
export function attachmentIds(messages: Array<{ attachments: unknown }>): Set<string> {
  const ids = new Set<string>();
  for (const m of messages) {
    if (!Array.isArray(m.attachments)) continue;
    for (const a of m.attachments) {
      if (a && typeof a === "object" && !Array.isArray(a) && "id" in a && a.id != null) {
        ids.add(typeof a.id === "string" ? a.id : JSON.stringify(a.id));
      }
    }
  }
  return ids;
}

/** Splits [items] into chunks of [size]. */
export function chunks<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/**
 * Deletes the caller's chats among [ids] with everything that belongs to
 * them: messages and recall index rows (ON DELETE CASCADE), the pending
 * recall job, and the files attached in them (storage objects and rows).
 * A file another of the caller's chats still uses (forks share attachments
 * by reference) stays and moves to that chat. Ids that are not the caller's
 * are ignored. Returns how many chats were deleted.
 */
export async function deleteConversations(ids: string[], uid: string | null): Promise<number> {
  let deleted = 0;
  for (const batch of chunks([...new Set(ids)], DELETE_BATCH)) deleted += await deleteBatch(batch, uid);
  return deleted;
}

async function deleteBatch(ids: string[], uid: string | null): Promise<number> {
  const { owned, doomed } = await tx(async (c) => {
    const rows = await c.conversation.findMany({ where: { id: { in: ids }, userId: uid }, select: { id: true } });
    const owned = rows.map((r) => r.id);
    if (owned.length === 0) return { owned, doomed: [] as string[] };
    const [msgs, files] = await Promise.all([
      c.conversationMessage.findMany({ where: { conversationId: { in: owned } }, select: { attachments: true } }),
      c.storedFile.findMany({ where: { conversationId: { in: owned } }, select: { id: true } }),
    ]);
    const attached = attachmentIds(msgs);
    for (const f of files) attached.add(f.id);
    const fileIds = [...attached];
    // One query for every file: is it still attached in another of the caller's chats?
    // Raw: expanding the jsonb attachments arrays has no Prisma equivalent.
    const users = fileIds.length
      ? await c.$queryRaw<Array<{ file_id: string; conversation_id: string }>>`
          SELECT DISTINCT ON (e->>'id') e->>'id' AS file_id, m.conversation_id::text AS conversation_id
            FROM conversation_messages m
            JOIN conversations cv ON cv.id = m.conversation_id
            CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(m.attachments) = 'array' THEN m.attachments ELSE '[]'::jsonb END) e
           WHERE cv.user_id IS NOT DISTINCT FROM ${uid}::uuid
             AND m.conversation_id <> ALL(${owned}::uuid[])
             AND jsonb_typeof(e) = 'object'
             AND e->>'id' = ANY(${fileIds}::text[])
           ORDER BY e->>'id', m.conversation_id`
      : [];
    const keep = new Map(users.map((u) => [u.file_id, u.conversation_id]));
    // Kept files move to a chat that still uses them (grouped: one update per receiving chat).
    const moves = new Map<string, string[]>();
    for (const [fileId, to] of keep) {
      if (!FILE_ID_RE.test(fileId)) continue; // file ids are uuids; anything else cannot match a files row
      moves.set(to, [...(moves.get(to) ?? []), fileId]);
    }
    for (const [to, moved] of moves) {
      await c.storedFile.updateMany({ where: { id: { in: moved }, conversationId: { in: owned }, userId: uid }, data: { conversationId: to } });
    }
    await c.conversation.deleteMany({ where: { id: { in: owned } } });
    return { owned, doomed: fileIds.filter((f) => !keep.has(f) && FILE_ID_RE.test(f)) };
  });
  for (const id of owned) cancelIndex(id);
  if (doomed.length) {
    const rows = await db().storedFile.findMany({ where: { id: { in: doomed }, userId: uid }, select: INFO_SELECT });
    // Storage deletes are network calls: a few at a time; one failure does not stop the rest.
    for (const group of chunks(rows, FILE_CONCURRENCY)) {
      await Promise.all(
        group.map((r) =>
          deleteFile(toFileRow(r)).catch((e) => log.warn("chat file delete failed", { id: r.id, message: (e as Error).message.slice(0, 120) })),
        ),
      );
    }
  }
  return owned.length;
}

/**
 * Which chats "delete all" takes: archived and pinned chats unless left out;
 * `archivedOnly` takes just the archived ones (the archive view's "select all").
 */
export type DeleteAllFilter = { includeArchived: boolean; includePinned: boolean; archivedOnly: boolean };

/** Ids of the caller's chats matching [f] (for deleting them all). */
export async function conversationIdsFor(uid: string | null, f: DeleteAllFilter): Promise<string[]> {
  const rows = await db().conversation.findMany({
    where: {
      userId: uid,
      ...(f.archivedOnly ? { archivedAt: { not: null } } : f.includeArchived ? {} : { archivedAt: null }),
      ...(f.includePinned ? {} : { pinnedAt: null }),
    },
    select: { id: true },
  });
  return rows.map((r) => r.id);
}
