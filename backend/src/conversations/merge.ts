import type { Message } from "../providers.js";
import { ask } from "./ask.js";
import { log } from "../util/logger.js";

// Same small, high-quota models as titles: a merge must not spend the OpenRouter daily quota.
const MERGE_MODELS = ["groq:openai/gpt-oss-20b", "ollama:gpt-oss:20b", "ollama:gemma4:31b"];
const TIMEOUT_MS = 45_000;
const CHAT_BUDGET = 12_000;
const FIRST_USER_MAX = 2_000;
const MAX_BRIEFING = 6_000;

const PROMPT =
  "You merge two chat transcripts into one briefing that a different assistant will read before continuing the conversation. " +
  "At most 600 words, plain Markdown, sections: '## Chat A: <title>', '## Chat B: <title>' " +
  "(each: goal, key facts, decisions, code/numbers that matter, open questions), then '## Connections'. " +
  "Preserve exact names, figures, URLs and code identifiers. Do not invent anything. Do not address the user. " +
  "Output only the briefing.";

export type MergeMessage = {
  role: string;
  content: string;
  isError: boolean;
  attachments: Array<{ name?: unknown }>;
};

export type MergeChat = { id: string; title: string; messages: MergeMessage[] };

const ROLE_LABEL: Record<string, string> = { user: "User", assistant: "Assistant", context: "Background" };

function render(m: MergeMessage, max = Infinity): string {
  const names = (m.attachments ?? []).map((a) => (typeof a.name === "string" ? a.name : "")).filter(Boolean);
  const files = names.length > 0 ? `\n[attached: ${names.join(", ")}]` : "";
  const body = m.content.length > max ? `${m.content.slice(0, max)}…` : m.content;
  return `${ROLE_LABEL[m.role] ?? m.role}: ${body}${files}`;
}

/** Title, first user message and as many of the most recent turns as fit the budget. */
export function transcript(chat: MergeChat, budget = CHAT_BUDGET): string {
  const msgs = chat.messages.filter((m) => !m.isError && (m.content.trim() || m.attachments?.length));
  const firstUserIdx = msgs.findIndex((m) => m.role === "user");
  const head = [`Title: ${chat.title}`];
  if (firstUserIdx >= 0) head.push(render(msgs[firstUserIdx], FIRST_USER_MAX));
  let used = head.join("\n\n").length;
  const tail: string[] = [];
  for (let i = msgs.length - 1; i > firstUserIdx; i--) {
    const remaining = budget - used - 2;
    if (remaining < 200) break;
    const line = render(msgs[i], remaining - 20);
    tail.unshift(line);
    used += line.length + 2;
  }
  const skipped = firstUserIdx >= 0 && tail.length < msgs.length - firstUserIdx - 1;
  return [...head, ...(skipped ? ["[… earlier turns omitted …]"] : []), ...tail].join("\n\n").slice(0, budget);
}

function cleanBriefing(raw: string): string {
  const text = raw.replace(/<think>[\s\S]*?(<\/think>|$)/gi, "").trim();
  return text.length > MAX_BRIEFING ? `${text.slice(0, MAX_BRIEFING - 1).trimEnd()}…` : text;
}

function clip(s: string, max: number): string {
  const t = s.trim();
  return t.length > max ? `${t.slice(0, max - 1).trimEnd()}…` : t;
}

/** Deterministic briefing when no model answers: title, opening question and latest reply of each chat. */
export function fallbackBriefing(a: MergeChat, b: MergeChat): string {
  const section = (label: string, chat: MergeChat) => {
    const ok = chat.messages.filter((m) => !m.isError);
    const firstUser = ok.find((m) => m.role === "user")?.content ?? "";
    const lastReply = [...ok].reverse().find((m) => m.role === "assistant")?.content ?? "";
    const parts = [`## Chat ${label}: ${chat.title}`];
    if (firstUser.trim()) parts.push(`**Started with:** ${clip(firstUser, 400)}`);
    if (lastReply.trim()) parts.push(`**Latest reply:**\n\n${clip(lastReply, 1200)}`);
    return parts.join("\n\n");
  };
  return `${section("A", a)}\n\n${section("B", b)}`;
}

/** Briefing that combines two chats. Never throws. */
export async function mergeBriefing(a: MergeChat, b: MergeChat): Promise<{ text: string; source: "ai" | "fallback" }> {
  const messages: Message[] = [
    { role: "system", content: PROMPT },
    { role: "user", content: `# Chat A\n\n${transcript(a)}\n\n# Chat B\n\n${transcript(b)}` },
  ];
  for (const model of MERGE_MODELS) {
    try {
      const text = cleanBriefing(await ask(model, messages, TIMEOUT_MS));
      if (text) return { text, source: "ai" };
    } catch (e) {
      log.warn("merge briefing failed", { model, message: (e as Error).message?.slice(0, 120) });
    }
  }
  return { text: fallbackBriefing(a, b), source: "fallback" };
}
