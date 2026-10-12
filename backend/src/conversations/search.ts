import { db, Prisma } from "../db/prisma.js";
import { escapeLike, fuzzyTerms, needsFuzzy, snippetAround, tsQueryText } from "../nlp/text.js";

export type SearchOpts = { uid: string | null; q: string; archived: boolean; before: Date | null; limit: number };
export type Snippet = { text: string; start: number; length: number; source: "message" | "title" };

// Raw SQL: Postgres full-text search (stemming, via the expression index on
// conversation_messages) and pg_trgm similarity have no Prisma filter.
// Indexes: see migration 20261012160000_nlp_search_indexes.
const MSG_TSV = Prisma.sql`to_tsvector('english', left(m.content, 100000))`;

/**
 * Conversation ids matching [q], pinned first then by activity. Stemmed full-text
 * match (with tech-term synonyms) plus a title substring match; when that finds
 * few chats, a trigram typo fallback on titles and messages is merged in.
 */
export async function searchConversationIds(o: SearchOpts): Promise<string[]> {
  const scope = Prisma.sql`c.user_id IS NOT DISTINCT FROM ${o.uid}::uuid
    AND ${o.archived ? Prisma.sql`c.archived_at IS NOT NULL` : Prisma.sql`c.archived_at IS NULL`}
    ${o.before ? Prisma.sql`AND c.updated_at < ${o.before}` : Prisma.empty}`;
  const order = Prisma.sql`ORDER BY c.pinned_at DESC NULLS LAST, c.updated_at DESC LIMIT ${o.limit}`;
  const tsq = tsQueryText(o.q);
  const fts = tsq
    ? Prisma.sql`OR to_tsvector('english', coalesce(c.title, '')) @@ websearch_to_tsquery('english', ${tsq})
        OR EXISTS (SELECT 1 FROM conversation_messages m WHERE m.conversation_id = c.id AND ${MSG_TSV} @@ websearch_to_tsquery('english', ${tsq}))`
    : Prisma.empty;
  const rows = await db().$queryRaw<Array<{ id: string }>>`
    SELECT c.id::text AS id FROM conversations c
    WHERE ${scope} AND (c.title ILIKE ${"%" + escapeLike(o.q) + "%"} ${fts})
    ${order}`;
  const ids = rows.map((r) => r.id);
  const terms = fuzzyTerms(o.q);
  if (!needsFuzzy(ids.length) || terms.length === 0) return ids;

  // Typo tolerance: `term <% content` is the indexable word_similarity operator.
  const anyTerm = Prisma.join(
    terms.map((t) => Prisma.sql`(word_similarity(${t}, c.title) >= 0.4 OR EXISTS (SELECT 1 FROM conversation_messages m WHERE m.conversation_id = c.id AND ${t} <% m.content))`),
    " OR ",
  );
  const fuzzy = await db().$queryRaw<Array<{ id: string }>>`
    SELECT c.id::text AS id FROM conversations c WHERE ${scope} AND (${anyTerm}) ${order}`;
  const seen = new Set(ids);
  for (const r of fuzzy) if (!seen.has(r.id)) ids.push(r.id);
  return ids.slice(0, o.limit);
}

/** The best matching message (or the title) of each conversation, as a short excerpt around the match. */
export async function snippetsFor(ids: string[], q: string): Promise<Map<string, Snippet>> {
  const out = new Map<string, Snippet>();
  if (ids.length === 0) return out;
  const tsq = tsQueryText(q);
  const terms = fuzzyTerms(q);
  const conds = [
    tsq ? Prisma.sql`${MSG_TSV} @@ websearch_to_tsquery('english', ${tsq})` : null,
    Prisma.sql`m.content ILIKE ${"%" + escapeLike(q) + "%"}`,
    ...terms.map((t) => Prisma.sql`${t} <% m.content`),
  ].filter((c): c is Prisma.Sql => c !== null);
  const rows = await db().$queryRaw<Array<{ conversation_id: string; content: string }>>`
    SELECT DISTINCT ON (m.conversation_id) m.conversation_id::text AS conversation_id, m.content
    FROM conversation_messages m
    WHERE m.conversation_id = ANY(${ids}::uuid[]) AND m.role <> 'context' AND (${Prisma.join(conds, " OR ")})
    ORDER BY m.conversation_id, (${MSG_TSV} @@ websearch_to_tsquery('english', ${tsq || q})) DESC, m.position`;
  for (const r of rows) {
    const s = snippetAround(r.content, q);
    if (s) out.set(r.conversation_id, { text: s.snippet, start: s.start, length: s.length, source: "message" });
  }
  return out;
}
