import { db } from "../db/prisma.js";
import type { UserCrypto } from "../crypto/userData.js";
import { expandQuery, fuzzyScore, fuzzyTerms, needsFuzzy, snippetAround, stem, tokenize } from "../nlp/text.js";
import { CONV, MSG } from "./codec.js";

export type SearchOpts = { uid: string | null; q: string; archived: boolean; before: Date | null; limit: number; crypto: UserCrypto };
export type Snippet = { text: string; start: number; length: number; source: "message" | "title" };
export type SearchHit = { id: string; snippet: Snippet | null };

/**
 * Chat search runs in the app on decrypted text, scoped to the caller: titles and message bodies are
 * ciphertext in the database, so SQL (ILIKE, to_tsvector, trigrams) cannot see them any more. Chats are
 * visited in list order (pinned, then newest) in pages, stopping once [limit] hits are found, and at most
 * MAX_SCAN_CHATS chats are looked at per query. The matcher mirrors the old SQL behaviour: substring, stemmed
 * any-term match with tech synonyms, then a typo-tolerant pass when few chats matched.
 */
export const MAX_SCAN_CHATS = 1000;
const PAGE = 25;
const MAX_CHARS_PER_MESSAGE = 100_000;

/** Pure matcher for one query; `fuzzy` additionally accepts typos (Damerau) on words of 4+ letters. */
export function queryMatcher(q: string): (text: string, fuzzy?: boolean) => boolean {
  const needle = q.trim().toLowerCase();
  const wanted = new Set(
    expandQuery(q)
      .flatMap((t) => tokenize(t))
      .filter((t) => t.length >= 2)
      .map(stem),
  );
  const typoTerms = fuzzyTerms(q);
  return (text, fuzzy = false) => {
    if (!text) return false;
    const hay = text.length > MAX_CHARS_PER_MESSAGE ? text.slice(0, MAX_CHARS_PER_MESSAGE) : text;
    if (needle && hay.toLowerCase().includes(needle)) return true;
    const tokens = tokenize(hay);
    if (tokens.some((t) => wanted.has(stem(t)))) return true;
    return fuzzy && typoTerms.some((t) => fuzzyScore(t, hay) > 0);
  };
}

/** Decrypted view of one chat for matching: its title and messages in position order. */
export type SearchableChat = { id: string; title: string; messages: Array<{ role: string; content: string }> };

/** Pure: does [chat] match, and what is the excerpt? */
export function matchChat(chat: SearchableChat, q: string, matcher: ReturnType<typeof queryMatcher>, fuzzy: boolean): SearchHit | null {
  const titleHit = matcher(chat.title, fuzzy);
  let snippet: Snippet | null = null;
  let messageHit = false;
  for (const m of chat.messages) {
    if (!matcher(m.content, fuzzy)) continue;
    messageHit = true;
    if (m.role === "context") continue;
    const s = snippetAround(m.content, q);
    if (s) {
      snippet = { text: s.snippet, start: s.start, length: s.length, source: "message" };
      break;
    }
  }
  return titleHit || messageHit ? { id: chat.id, snippet } : null;
}

/** Chats matching [q] in list order (pinned first, then by activity), each with the best matching excerpt. */
export async function searchConversations(o: SearchOpts): Promise<SearchHit[]> {
  const matcher = queryMatcher(o.q);
  const scan = async (fuzzy: boolean, skipIds: Set<string>): Promise<SearchHit[]> => {
    const hits: SearchHit[] = [];
    for (let skip = 0; skip < MAX_SCAN_CHATS && hits.length < o.limit; skip += PAGE) {
      const page = await db().conversation.findMany({
        where: { userId: o.uid, archivedAt: o.archived ? { not: null } : null, ...(o.before ? { updatedAt: { lt: o.before } } : {}) },
        orderBy: [{ pinnedAt: { sort: "desc", nulls: "last" } }, { updatedAt: "desc" }],
        skip,
        take: PAGE,
        select: { id: true, title: true },
      });
      if (page.length === 0) break;
      const msgs = await db().conversationMessage.findMany({
        where: { conversationId: { in: page.map((p) => p.id) } },
        orderBy: [{ conversationId: "asc" }, { position: "asc" }],
        select: { conversationId: true, role: true, content: true },
      });
      const byChat = new Map<string, Array<{ role: string; content: string }>>();
      for (const m of msgs) {
        const list = byChat.get(m.conversationId) ?? [];
        list.push({ role: m.role, content: o.crypto.open(MSG, "content", m.content) });
        byChat.set(m.conversationId, list);
      }
      for (const p of page) {
        if (skipIds.has(p.id) || hits.length >= o.limit) continue;
        const hit = matchChat({ id: p.id, title: p.title ? o.crypto.open(CONV, "title", p.title) : "", messages: byChat.get(p.id) ?? [] }, o.q, matcher, fuzzy);
        if (hit) hits.push(hit);
      }
      if (page.length < PAGE) break;
    }
    return hits;
  };

  const exact = await scan(false, new Set());
  if (!needsFuzzy(exact.length) || fuzzyTerms(o.q).length === 0) return exact;
  // Typo tolerance when few chats matched; exact hits keep their place at the front.
  const seen = new Set(exact.map((h) => h.id));
  const fuzzy = await scan(true, seen);
  return [...exact, ...fuzzy].slice(0, o.limit);
}
