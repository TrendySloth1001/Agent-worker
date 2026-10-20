import type { ChatEvent } from "../schemas/events";
import { SEARCHED_META_KEY, SUGGESTIONS_META_KEY, type StoredMessage } from "../schemas/message";
import { emptyMessage, type ChatState, type UiMessage } from "./types";

export type ChatAction =
  | { type: "load"; messages: UiMessage[] }
  | { type: "send"; user: UiMessage; assistant: UiMessage }
  | { type: "append"; message: UiMessage }
  | { type: "event"; id: string; event: ChatEvent }
  | { type: "fail"; id: string; message: string }
  | { type: "stop"; id: string }
  | { type: "truncate"; keep: number }
  | { type: "dismiss-toggle"; id: string };

export const initialChatState: ChatState = { messages: [] };

export function pendingAssistant(id: string): UiMessage {
  return { ...emptyMessage(id, "assistant"), streaming: true };
}

export function applyEvent(m: UiMessage, event: ChatEvent): UiMessage {
  switch (event.type) {
    case "start":
      return { ...m, candidates: event.data.candidates, waitLast: "start" };
    case "status":
      return { ...m, phase: event.data.phase, waitLast: "status" };
    case "model":
      return { ...m, modelId: event.data.model, attempt: event.data.attempt, waitLast: "model" };
    case "delta":
      return { ...m, content: m.content + event.data.text };
    case "reset":
      return { ...m, content: "" };
    case "notice":
      return { ...m, notice: event.data.message };
    case "tools":
      return { ...m, webSearched: event.data.web };
    case "sources":
      return { ...m, citations: event.data.citations };
    case "evidence":
      return { ...m, evidence: event.data.items };
    case "images":
      return { ...m, images: event.data.images };
    case "table":
      return { ...m, tablePhase: event.data.phase };
    case "suggestions":
      return { ...m, suggestions: event.data.items.map((s) => s.trim()).filter(Boolean) };
    case "suggest_toggle":
      return { ...m, toggle: event.data };
    case "memory":
      return { ...m, memoryOps: event.data.changes.map((c) => c.op) };
    case "usage":
      return { ...m, tokens: event.data.promptTokens + event.data.completionTokens };
    case "done":
      return {
        ...m,
        streaming: false,
        modelId: event.data.model ?? m.modelId,
        usedIds: event.data.used,
        latencyMs: event.data.latencyMs,
      };
    case "error":
      return {
        ...m,
        streaming: false,
        isError: m.content === "",
        interrupted: false,
        error: event.data.error.message,
      };
  }
}

const mapMessage = (
  state: ChatState,
  id: string,
  fn: (m: UiMessage) => UiMessage,
): ChatState => ({
  messages: state.messages.map((m) => (m.id === id ? fn(m) : m)),
});

export function chatReducer(state: ChatState, action: ChatAction): ChatState {
  switch (action.type) {
    case "load":
      return { messages: action.messages };
    case "send":
      return { messages: [...state.messages, action.user, action.assistant] };
    case "append":
      return { messages: [...state.messages, action.message] };
    case "event":
      return mapMessage(state, action.id, (m) => applyEvent(m, action.event));
    case "fail":
      return mapMessage(state, action.id, (m) => ({
        ...m,
        streaming: false,
        isError: m.content === "",
        interrupted: true,
        error: action.message,
      }));
    case "stop":
      return mapMessage(state, action.id, (m) =>
        m.streaming
          ? { ...m, streaming: false, isError: m.content === "", interrupted: m.content === "" }
          : m,
      );
    case "truncate":
      return { messages: state.messages.slice(0, action.keep) };
    case "dismiss-toggle":
      return mapMessage(state, action.id, (m) => ({ ...m, toggle: undefined }));
  }
}

export function fromStored(stored: StoredMessage, id: string): UiMessage {
  const suggestions = stored.meta[SUGGESTIONS_META_KEY];
  return {
    ...emptyMessage(id, stored.role),
    content: stored.content,
    isError: stored.isError,
    modelId: stored.model ?? undefined,
    citations: stored.citations,
    usedIds: stored.usedIds,
    images: stored.images,
    evidence: stored.evidence,
    attachments: stored.attachments,
    suggestions: Array.isArray(suggestions)
      ? suggestions.filter((s): s is string => typeof s === "string" && s.trim() !== "")
      : [],
    webSearched: stored.meta[SEARCHED_META_KEY] === true,
  };
}

export function toStored(m: UiMessage): StoredMessage {
  const meta: Record<string, unknown> = {};
  if (m.suggestions.length > 0) meta[SUGGESTIONS_META_KEY] = m.suggestions;
  if (m.webSearched) meta[SEARCHED_META_KEY] = true;
  return {
    role: m.role,
    content: m.content || m.error || "",
    model: m.modelId ?? null,
    meta,
    citations: m.citations,
    usedIds: m.usedIds,
    images: m.images,
    evidence: m.evidence,
    attachments: m.attachments,
    isError: m.isError,
  };
}
