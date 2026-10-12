// The SQL for cross-chat recall. Kept as builders (no database access) so the
// scoping rules can be tested: every query is limited to the caller's own chats,
// never includes the current conversation, and skips archived ones.
import { Prisma } from "../db/prisma.js";
import { toVector } from "../db/vector.js";

export type RecallRow = {
  conversation_id: string;
  ord: number;
  kind: string;
  content: string;
  sim: number;
  title: string | null;
  updated_at: Date;
};

export type SearchSql = { uid: string | null; vec: number[]; excludeConversationId?: string | null; limit: number };

/** Nearest chunks of the user's other, non-archived chats (cosine, served by the HNSW index). */
export function searchSql(o: SearchSql): Prisma.Sql {
  const v = toVector(o.vec);
  // Both the chunk and its chat must belong to the user: a stale chunk can never leak across accounts.
  const exclude = o.excludeConversationId ? Prisma.sql`AND cc.conversation_id <> ${o.excludeConversationId}::uuid` : Prisma.empty;
  return Prisma.sql`
    SELECT cc.conversation_id::text AS conversation_id, cc.ord, cc.kind, cc.content,
           1 - (cc.embedding <=> ${v}::vector) AS sim, c.title, c.updated_at
    FROM conversation_chunks cc
    JOIN conversations c ON c.id = cc.conversation_id
    WHERE cc.user_id IS NOT DISTINCT FROM ${o.uid}::uuid
      AND c.user_id IS NOT DISTINCT FROM ${o.uid}::uuid
      AND c.archived_at IS NULL
      ${exclude}
    ORDER BY cc.embedding <=> ${v}::vector
    LIMIT ${o.limit}`;
}

/** Inserts one chunk, replacing the same (conversation, ord) slot. */
export function upsertSql(c: { conversationId: string; uid: string | null; ord: number; kind: string; content: string; hash: string; vec: number[] }): Prisma.Sql {
  return Prisma.sql`
    INSERT INTO conversation_chunks (conversation_id, user_id, ord, kind, content, content_hash, embedding)
    VALUES (${c.conversationId}::uuid, ${c.uid}::uuid, ${c.ord}, ${c.kind}, ${c.content}, ${c.hash}, ${toVector(c.vec)}::vector)
    ON CONFLICT (conversation_id, ord) DO UPDATE
      SET kind = EXCLUDED.kind, content = EXCLUDED.content, content_hash = EXCLUDED.content_hash,
          embedding = EXCLUDED.embedding, user_id = EXCLUDED.user_id`;
}
