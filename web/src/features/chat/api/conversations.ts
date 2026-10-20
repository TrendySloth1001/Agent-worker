import { z } from "zod";
import {
  conversationListSchema,
  conversationSchema,
  conversationSummarySchema,
  type Conversation,
  type ConversationSummary,
} from "../schemas/conversation";
import type { StoredMessage } from "../schemas/message";
import { apiFetch, apiJson, jsonBody } from "./http";

export const LIST_LIMIT = 100;

export async function listConversations(query: string): Promise<ConversationSummary[]> {
  const params = new URLSearchParams({ limit: String(LIST_LIMIT) });
  if (query) params.set("q", query);
  const { conversations } = await apiJson(`/conversations?${params}`, conversationListSchema);
  return conversations;
}

export const getConversation = (id: string): Promise<Conversation> =>
  apiJson(`/conversations/${id}`, conversationSchema);

export async function saveConversation(id: string, messages: StoredMessage[]): Promise<void> {
  await apiFetch(`/conversations/${id}`, jsonBody("PUT", { messages }));
}

export const renameConversation = (id: string, title: string): Promise<ConversationSummary> =>
  apiJson(`/conversations/${id}`, conversationSummarySchema, jsonBody("PATCH", { title }));

export const pinConversation = (id: string, pinned: boolean): Promise<ConversationSummary> =>
  apiJson(`/conversations/${id}`, conversationSummarySchema, jsonBody("PATCH", { pinned }));

export async function deleteConversation(id: string): Promise<void> {
  await apiFetch(`/conversations/${id}`, { method: "DELETE" });
}

export const startersSchema = z.object({ prompts: z.array(z.string()) });

export async function fetchStarters(): Promise<string[]> {
  const { prompts } = await apiJson("/assist/starters", startersSchema);
  return prompts;
}
