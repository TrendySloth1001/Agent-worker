// Conversation context for tools that run outside a chat request (documents
// generated from a chat): read from the saved conversation of the caller.
import { db } from "../db/prisma.js";
import { renderContext, trimTurns, extractTopics, type TurnMessage } from "./turnContext.js";

/** Short text describing what a saved chat is about (title, summary, topics, latest turns); "" when unknown. Owner-scoped. */
export async function storedConversationContext(conversationId: string, userId: string): Promise<string> {
  const conv = await db().conversation.findFirst({
    where: { id: conversationId, userId },
    select: { title: true, summary: true, messages: { orderBy: { position: "desc" }, take: 14, select: { role: true, content: true, isError: true } } },
  });
  if (!conv) return "";
  const messages: TurnMessage[] = conv.messages
    .reverse()
    .filter((m) => (m.role === "user" || m.role === "assistant") && !m.isError && m.content.trim())
    .map((m) => ({ role: m.role as "user" | "assistant", content: m.content }));
  const rendered = renderContext({ summary: conv.summary, topics: extractTopics(messages), turns: trimTurns(messages) }, "doc");
  return [conv.title ? `Chat title: ${conv.title}` : "", rendered].filter(Boolean).join("\n");
}
