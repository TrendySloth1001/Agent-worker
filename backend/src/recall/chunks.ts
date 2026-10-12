// How a saved conversation becomes searchable pieces: one header chunk (title +
// summary) and one chunk per exchange (a user message with the reply to it).
// Pure and deterministic, so appending messages only adds chunks and unchanged
// ones keep their hash (and are not embedded again).
import { createHash } from "node:crypto";

export type ChunkMessage = { role: string; content: string; isError?: boolean };
export type ConvChunk = { ord: number; kind: "header" | "turn"; content: string; hash: string };

export const USER_CHARS = 700;
export const ASSISTANT_CHARS = 1100;
/** Exchanges indexed per chat (the header's summary covers the rest). */
export const MAX_TURNS = 59;
const HEADER_CHARS = 1400;
const PLACEHOLDER = "(no message text, only attachments)";

const clip = (s: string, n: number) => {
  const t = s.replace(/\s+/g, " ").trim();
  return t.length > n ? `${t.slice(0, n - 1)}…` : t;
};
const sha = (s: string) => createHash("sha1").update(s).digest("hex");

export function buildChunks(input: { title?: string | null; summary?: string | null; preview?: string | null; messages: ChunkMessage[] }): ConvChunk[] {
  const out: ConvChunk[] = [];
  const title = input.title?.trim() || input.preview?.trim() || "";
  const body = input.summary?.trim() || "";
  const header = clip(`Chat: ${title}${body ? `\nSummary: ${body}` : ""}`, HEADER_CHARS);
  if (title || body) out.push({ ord: 0, kind: "header", content: header, hash: sha(`header\0${header}`) });

  const msgs = input.messages.filter((m) => (m.role === "user" || m.role === "assistant") && !m.isError && m.content.trim() && m.content.trim() !== PLACEHOLDER);
  let turns = 0;
  for (let i = 0; i < msgs.length && turns < MAX_TURNS; i++) {
    if (msgs[i].role !== "user") continue;
    const reply = msgs[i + 1]?.role === "assistant" ? msgs[i + 1] : null;
    const text = `User: ${clip(msgs[i].content, USER_CHARS)}${reply ? `\nAssistant: ${clip(reply.content, ASSISTANT_CHARS)}` : ""}`;
    turns++;
    out.push({ ord: turns, kind: "turn", content: text, hash: sha(`turn\0${text}`) });
  }
  return out;
}

/** What to delete and what to (re)embed to turn the [existing] rows (ord -> hash) into [wanted]. */
export function diffChunks(existing: Map<number, string>, wanted: ConvChunk[]): { remove: number[]; add: ConvChunk[] } {
  const keep = new Set(wanted.map((c) => c.ord));
  const remove = [...existing.keys()].filter((o) => !keep.has(o) || existing.get(o) !== wanted.find((c) => c.ord === o)?.hash);
  const removed = new Set(remove);
  const add = wanted.filter((c) => !existing.has(c.ord) || removed.has(c.ord));
  return { remove, add };
}
