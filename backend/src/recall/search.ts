// Finds past conversations that matter for this turn and renders them as a
// short "Related past conversations" block with [C#] tags.
import { currentUser } from "../auth/context.js";
import { getEmbeddingGuardError } from "../db/embeddingGuard.js";
import { db, isDbUp, tx } from "../db/prisma.js";
import { embedQueries } from "../embeddings/index.js";
import { config } from "../config.js";
import { log } from "../util/logger.js";
import { chatRecallEnabled } from "./index.js";
import { searchSql, type RecallRow } from "./sql.js";

/** Auto mode only surfaces a chat when it is clearly about the same thing. */
export const AUTO_MIN_SIM = config.chatRecallMinSim;
/** When the user asks about earlier chats, weaker matches are still worth showing. */
export const EXPLICIT_MIN_SIM = 0.3;
const AUTO_CHATS = 2;
const EXPLICIT_CHATS = 4;
const AUTO_CHARS = 1800;
const EXPLICIT_CHARS = 3600;
const EXCERPT_CHARS = 520;
const CANDIDATES = 24;

export type PastChat = { id: string; title: string; updatedAt: Date; sim: number; excerpts: string[] };
export type PastCitation = { id: string; title: string; url: string; snippet: string; date: string; conversationId: string };

/** "12 Oct 2026" (UTC, stable across servers). */
export function formatDate(d: Date): string {
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
}

/** Rows (best first) to at most [maxChats] chats at or above [minSim], each with its best excerpts. */
export function groupRows(rows: RecallRow[], o: { minSim: number; maxChats: number; perChat?: number }): PastChat[] {
  const byChat = new Map<string, PastChat>();
  for (const r of rows) {
    const sim = Number(r.sim);
    if (sim < o.minSim) continue;
    let chat = byChat.get(r.conversation_id);
    if (!chat) {
      if (byChat.size >= o.maxChats) continue;
      chat = { id: r.conversation_id, title: r.title?.trim() || "Untitled chat", updatedAt: new Date(r.updated_at), sim, excerpts: [] };
      byChat.set(r.conversation_id, chat);
    }
    if (chat.excerpts.length < (o.perChat ?? 2)) chat.excerpts.push(r.kind === "header" ? r.content.replace(/^Chat: .*\n?/, "").replace(/^Summary: /, "").trim() || r.content : r.content);
  }
  return [...byChat.values()];
}

const clip = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1)}…` : s);

/** The context block and its citations, within [budgetChars]. Null when there is nothing to show. */
export function formatPastBlock(chats: PastChat[], budgetChars: number): { block: string; citations: PastCitation[] } | null {
  const citations: PastCitation[] = [];
  const parts: string[] = [];
  let used = 0;
  for (const chat of chats) {
    const id = `C${citations.length + 1}`;
    const head = `[${id}] Chat "${chat.title.replace(/"/g, "'")}" (${formatDate(chat.updatedAt)})`;
    let body = "";
    for (const ex of chat.excerpts) {
      const line = clip(ex.replace(/<\/?past_conversations>/gi, ""), EXCERPT_CHARS);
      if (used + head.length + body.length + line.length > budgetChars && (body || parts.length)) break;
      body += `\n${line}`;
    }
    if (!body) continue;
    used += head.length + body.length;
    parts.push(head + body);
    citations.push({ id, title: chat.title, url: `chat:${chat.id}`, snippet: clip(chat.excerpts[0].replace(/\s+/g, " "), 200), date: chat.updatedAt.toISOString(), conversationId: chat.id });
  }
  if (!parts.length) return null;
  const block = `Related past conversations (excerpts from this user's earlier chats, not this one; tags ${citations.map((c) => c.id).join(", ")}):\n<past_conversations>\n${parts.join("\n\n")}\n</past_conversations>`;
  return { block, citations };
}

export const NOT_FOUND_NOTE =
  "The user is asking about an earlier conversation, but searching their past chats found nothing relevant. Say so honestly in one short sentence and do not invent or guess what was said before.";
export const DISABLED_NOTE =
  "The user is asking about an earlier conversation, but cross-chat recall is switched off in their settings, so past chats were not searched. Say so briefly and mention they can turn it on in settings; do not guess what was said before.";

export type RecallResult = { block: string | null; citations: PastCitation[]; found: number; mode: "explicit" | "auto" };

export type RecallInput = {
  /** The self-contained question for this turn (src/context). */
  query: string;
  /** What an explicit reference is about ("my chat about Redis"), when known. */
  topic?: string;
  explicit: boolean;
  excludeConversationId?: string;
};

/** Searches the caller's other chats. Never throws; a failure reads as "nothing found" (explicit asks say so honestly). */
export async function recallPastChats(input: RecallInput): Promise<RecallResult> {
  const mode = input.explicit ? "explicit" : "auto";
  const empty: RecallResult = { block: input.explicit ? NOT_FOUND_NOTE : null, citations: [], found: 0, mode };
  const query = (input.explicit && (input.topic?.length ?? 0) >= 3 ? `${input.topic} ${input.query}` : input.query).trim().slice(0, 600);
  if (!query || !isDbUp()) return empty;
  try {
    const uid = currentUser()?.id ?? null;
    if (!(await chatRecallEnabled(uid))) return { ...empty, block: input.explicit ? DISABLED_NOTE : null };
    if (getEmbeddingGuardError()) return empty;
    const [vec] = await embedQueries([query]);
    const rows = await tx(async (c) => {
      await c.$executeRaw`SET LOCAL hnsw.ef_search = 60`;
      // Keep scanning the index until enough rows pass the per-user filter.
      await c.$executeRaw`SET LOCAL hnsw.iterative_scan = relaxed_order`;
      return c.$queryRaw<RecallRow[]>(searchSql({ uid, vec, excludeConversationId: input.excludeConversationId, limit: CANDIDATES }));
    });
    const chats = groupRows(rows, { minSim: input.explicit ? EXPLICIT_MIN_SIM : AUTO_MIN_SIM, maxChats: input.explicit ? EXPLICIT_CHATS : AUTO_CHATS });
    const out = formatPastBlock(chats, input.explicit ? EXPLICIT_CHARS : AUTO_CHARS);
    log.info("chat recall", { mode, rows: rows.length, chats: chats.length, top: rows[0] ? Math.round(Number(rows[0].sim) * 100) / 100 : 0 });
    return out ? { block: out.block, citations: out.citations, found: out.citations.length, mode } : empty;
  } catch (e) {
    log.warn("chat recall failed", { message: String((e as Error).message ?? e).slice(0, 140) });
    return empty;
  }
}
