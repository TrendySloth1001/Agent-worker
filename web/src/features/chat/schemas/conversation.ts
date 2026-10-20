import { z } from "zod";
import { storedMessageSchema } from "./message";

export const conversationSummarySchema = z.looseObject({
  id: z.string(),
  title: z.string().nullable().catch(null),
  messageCount: z.number().catch(0),
  preview: z.string().nullable().catch(null),
  pinned: z.boolean().catch(false),
  archived: z.boolean().catch(false),
  origin: z.string().nullable().catch(null),
  updatedAt: z.string(),
  createdAt: z.string().optional(),
  snippet: z.string().nullish(),
});

export const conversationSchema = conversationSummarySchema.extend({
  messages: z.array(storedMessageSchema),
});

export const conversationListSchema = z.object({
  conversations: z.array(conversationSummarySchema),
});

export type ConversationSummary = z.infer<typeof conversationSummarySchema>;
export type Conversation = z.infer<typeof conversationSchema>;
