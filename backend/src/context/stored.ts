// Conversation context for tools that run outside a chat request (documents
// generated from a chat): read from the saved conversation of the caller.
import { userCrypto } from "../crypto/userData.js";
import { CONV, MSG } from "../conversations/codec.js";
import { db } from "../db/prisma.js";
import { renderContext, trimTurns, extractTopics, type TurnMessage } from "./turnContext.js";

/** Short text describing what a saved chat is about (title, summary, topics, latest turns); "" when unknown. Owner-scoped. */
export async function storedConversationContext(conversationId: string, userId: string): Promise<string> {
  const conv = await db().conversation.findFirst({
    where: { id: conversationId, userId },
    select: { title: true, summary: true, messages: { orderBy: { position: "desc" }, take: 14, select: { role: true, content: true, isError: true } } },
  });
  if (!conv) return "";
  const c = await userCrypto(userId);
  const title = conv.title ? c.open(CONV, "title", conv.title) : null;
  const summary = conv.summary ? c.open(CONV, "summary", conv.summary) : null;
  const messages: TurnMessage[] = conv.messages
    .reverse()
    .map((m) => ({ ...m, content: c.open(MSG, "content", m.content) }))
    .filter((m) => (m.role === "user" || m.role === "assistant") && !m.isError && m.content.trim())
    .map((m) => ({ role: m.role as "user" | "assistant", content: m.content }));
  const rendered = renderContext({ summary, topics: extractTopics(messages), turns: trimTurns(messages) }, "doc");
  return [title ? `Chat title: ${title}` : "", rendered].filter(Boolean).join("\n");
}
