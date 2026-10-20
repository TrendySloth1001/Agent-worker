import { parseChatEvent, type ChatEvent } from "../schemas/events";
import { apiFetch, jsonBody } from "./http";
import { readSse } from "./sse";

export type WebMode = "auto" | "on" | "off";
export type SuggestKind = "kb" | "doc";

export interface ChatRequestMessage {
  role: "user" | "assistant";
  content: string;
  attachments?: string[];
}

export interface ChatRequest {
  messages: ChatRequestMessage[];
  conversationId?: string;
  model?: string;
  webMode: WebMode;
  knowledge: boolean;
  roundTable: boolean;
  suppressSuggest: SuggestKind[];
}

export type ChatStreamFn = (request: ChatRequest, signal: AbortSignal) => AsyncIterable<ChatEvent>;

export async function* streamChat(
  request: ChatRequest,
  signal: AbortSignal,
): AsyncGenerator<ChatEvent> {
  const res = await apiFetch("/chat", {
    ...jsonBody("POST", { ...request, smartSuggestions: true }),
    headers: { "Content-Type": "application/json", Accept: "text/event-stream" },
    signal,
  });
  if (!res.body) return;
  for await (const message of readSse(res.body)) {
    const event = parseChatEvent(message.event, message.data);
    if (event) yield event;
  }
}
