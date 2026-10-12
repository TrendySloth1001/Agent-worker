// Rolling conversation summary. The app sends the whole history with every
// turn; once it passes a token budget, the older turns are replaced by a short
// summary (cached on the conversation row, and extended incrementally) and only
// the recent turns are sent as messages.
import { createHash } from "node:crypto";
import { currentUser } from "../auth/context.js";
import { ask } from "../conversations/ask.js";
import { db, isDbUp } from "../db/prisma.js";
import { isUuid } from "../docs/store.js";
import { log } from "../util/logger.js";
import type { Message } from "../providers.js";

/** Estimated tokens above which older turns get summarized. */
export const BUDGET_TOKENS = 6000;
/** Recent messages always sent verbatim (at least), starting on a user turn. */
export const KEEP_MIN = 4;
export const KEEP_MAX = 10;
const SUMMARY_MODELS = ["groq:openai/gpt-oss-20b", "groq:openai/gpt-oss-120b", "ollama:gpt-oss:20b"];
const TIMEOUT_MS = 20_000;
const PER_MESSAGE_CHARS = 1500;
const INPUT_CHARS = 24_000;

type Turn = { role: "user" | "assistant"; content: string };

export const estimateTokens = (s: string) => Math.ceil(s.length / 4);

/**
 * Where to cut: messages before the returned index get summarized, the rest
 * stay verbatim. Null when the history fits the budget (or nothing is old enough).
 * The kept tail always starts on a user message.
 */
export function splitPoint(messages: Turn[], budget = BUDGET_TOKENS): number | null {
  const total = messages.reduce((n, m) => n + estimateTokens(m.content), 0);
  if (total <= budget || messages.length <= KEEP_MIN) return null;
  // Keep recent messages until about half the budget is used.
  let kept = 0;
  let keep = 0;
  for (let i = messages.length - 1; i >= 0 && keep < KEEP_MAX; i--) {
    kept += estimateTokens(messages[i].content);
    keep++;
    if (kept >= budget / 2 && keep >= KEEP_MIN) break;
  }
  keep = Math.max(keep, KEEP_MIN);
  let cut = messages.length - keep;
  while (cut < messages.length && messages[cut].role !== "user") cut++; // tail starts on a user turn
  return cut >= 1 && cut < messages.length ? cut : null;
}

/** Stable fingerprint of a message prefix: an edited or regenerated history no longer matches. */
export function fingerprint(messages: Turn[]): string {
  const h = createHash("sha1");
  for (const m of messages) h.update(`${m.role}\u0000${m.content}\u0001`);
  return h.digest("hex");
}

const SYSTEM =
  "You compress the older part of a chat between a user and an AI assistant into a running summary that replaces those messages. " +
  "Write plain text under 250 words as short bullet points. Keep: the user's goal, decisions and conclusions, names, numbers, file/function identifiers, constraints and preferences the user stated, and open questions or next steps. " +
  "Drop: pleasantries, repeated explanations, and long code (keep only what it does and key names). " +
  "If a previous summary is given, merge the new messages into it and keep it under the same length. Reply with the summary only.";

function render(turns: Turn[]): string {
  let out = "";
  for (const m of turns) {
    const line = `${m.role === "user" ? "User" : "Assistant"}: ${m.content.slice(0, PER_MESSAGE_CHARS)}\n\n`;
    if (out.length + line.length > INPUT_CHARS) break;
    out += line;
  }
  return out.trim();
}

async function summarize(previous: string | null, turns: Turn[]): Promise<string | null> {
  const messages: Message[] = [
    { role: "system", content: SYSTEM },
    { role: "user", content: `${previous ? `Previous summary:\n${previous}\n\nNew messages to merge in:\n` : "Messages:\n"}${render(turns)}` },
  ];
  for (const model of SUMMARY_MODELS) {
    try {
      const text = (await ask(model, messages, TIMEOUT_MS, "summary")).trim();
      if (text) return text.slice(0, 3000);
    } catch (e) {
      log.warn("summary failed", { model, message: (e as Error).message?.slice(0, 120) });
    }
  }
  return null;
}

// Fallback when the conversation row does not exist yet (the app saves after the first turns).
const mem = new Map<string, { summary: string; upto: number; hash: string }>();
const MEM_MAX = 200;

export type Compacted<T extends Turn> = { summary: string; recent: T[] };

/**
 * Summary + recent turns for a history over budget, or null (send everything).
 * Never throws; on any failure the full history is sent as before.
 */
export async function compactHistory<T extends Turn>(messages: T[], conversationId?: string, budget = BUDGET_TOKENS): Promise<Compacted<T> | null> {
  try {
    const cut = splitPoint(messages, budget);
    if (cut === null) return null;
    const older = messages.slice(0, cut);
    const recent = messages.slice(cut);
    const userId = currentUser()?.id ?? null;
    const dbId = conversationId && isUuid(conversationId) && userId && isDbUp() ? conversationId : null;
    const key = `${userId ?? ""}:${conversationId ?? ""}`;

    // Reuse the cached summary when it covers a still-identical prefix.
    let base: { summary: string; upto: number } | null = null;
    const cached = conversationId ? mem.get(key) : undefined;
    if (cached && cached.upto <= older.length && cached.hash === fingerprint(older.slice(0, cached.upto))) base = cached;
    if (!base && dbId) {
      const row = await db().conversation.findFirst({ where: { id: dbId, userId }, select: { summary: true, summaryUpto: true, summaryHash: true } });
      if (row?.summary && row.summaryUpto <= older.length && row.summaryHash === fingerprint(older.slice(0, row.summaryUpto))) {
        base = { summary: row.summary, upto: row.summaryUpto };
      }
    }
    if (base && base.upto === older.length) return { summary: base.summary, recent };

    const summary = await summarize(base?.summary ?? null, older.slice(base?.upto ?? 0));
    if (!summary) return null;

    const hash = fingerprint(older);
    if (conversationId) {
      mem.set(key, { summary, upto: older.length, hash });
      if (mem.size > MEM_MAX) mem.delete(mem.keys().next().value as string);
    }
    if (dbId) {
      // updateMany: a conversation that is not saved yet simply matches no row.
      void db()
        .conversation.updateMany({ where: { id: dbId, userId }, data: { summary, summaryUpto: older.length, summaryHash: hash } })
        .catch((e) => log.warn("summary save failed", { error: String(e).slice(0, 120) }));
    }
    return { summary, recent };
  } catch (e) {
    log.warn("history compaction failed", { error: String(e).slice(0, 120) });
    return null;
  }
}

export const summaryMessage = (summary: string): string =>
  `Summary of the earlier part of this conversation (those messages are omitted to save space; treat it as what was said before):\n\n${summary}`;
