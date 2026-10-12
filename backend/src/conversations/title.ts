import type { Message } from "../providers.js";
import { ask } from "./ask.js";
import { log } from "../util/logger.js";

// Small, fast models with generous quotas, so titles never spend the OpenRouter daily quota.
const TITLE_MODELS = ["groq:openai/gpt-oss-20b", "ollama:gpt-oss:20b", "ollama:gemma4:31b"];
const TIMEOUT_MS = 15_000;
const MAX_LENGTH = 60;

const PROMPT =
  "Write a short title (3 to 6 words) for this conversation. " +
  "Reply with the title only: no quotes, no trailing punctuation, no prefix like 'Title:'.";

/** Title from the first user message when no model answers. */
export function fallbackTitle(firstUser: string): string {
  const words = firstUser.replace(/https?:\/\/\S+/g, "").replace(/\s+/g, " ").trim().split(" ").slice(0, 6);
  const text = words.join(" ").replace(/[.,;:!?]+$/, "");
  return clean(text) || "New chat";
}

/** 3 to 5 words, no greeting or pronoun-only opener: the message itself reads as a title. */
export function isTitleReady(firstUser: string): boolean {
  const words = firstUser.replace(/https?:\/\/\S+/g, "").replace(/[?!.,]+$/g, "").trim().split(/\s+/).filter(Boolean);
  if (words.length < 3 || words.length > 5) return false;
  return !/^(hi|hello|hey|yo|ok|okay|so|and|but|can|could|please|help|what about|how about)\b/i.test(words.join(" ")) && !/\b(it|this|that|them|these|those)\b/i.test(words.join(" "));
}

function clean(raw: string): string {
  const line = raw.trim().split("\n").find((l) => l.trim()) ?? "";
  const text = line
    .replace(/^\s*(title)\s*:\s*/i, "")
    .replace(/^[\s"'`*#]+|[\s"'`*.]+$/g, "")
    .trim();
  if (!text) return "";
  const capped = text.length > MAX_LENGTH ? `${text.slice(0, MAX_LENGTH - 1).trimEnd()}…` : text;
  return capped.charAt(0).toUpperCase() + capped.slice(1);
}

/** Names a conversation from its opening exchange. Never throws. */
export async function generateTitle(firstUser: string, firstAssistant: string): Promise<{ title: string; source: "ai" | "fallback" }> {
  // A short, specific opening message ("rust async runtimes compared") is already a fine title: no model call.
  if (isTitleReady(firstUser)) return { title: fallbackTitle(firstUser), source: "fallback" };
  const messages: Message[] = [
    { role: "system", content: PROMPT },
    { role: "user", content: `User: ${firstUser.slice(0, 1500)}\n\nAssistant: ${firstAssistant.slice(0, 1500)}` },
  ];
  for (const model of TITLE_MODELS) {
    try {
      const title = clean(await ask(model, messages, TIMEOUT_MS, "title"));
      if (title) return { title, source: "ai" };
    } catch (e) {
      log.warn("title generation failed", { model, message: (e as Error).message?.slice(0, 120) });
    }
  }
  return { title: fallbackTitle(firstUser), source: "fallback" };
}
