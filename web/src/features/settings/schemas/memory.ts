import { z } from "zod";

export const MEMORY_KINDS = ["identity", "fact", "preference", "project", "instruction"] as const;
export const memoryKindSchema = z.enum(MEMORY_KINDS);
export type MemoryKind = z.infer<typeof memoryKindSchema>;

export const MEMORY_TEXT_MAX = 300;
export const MEMORY_TEXT_MIN = 2;

export const memorySchema = z.object({
  id: z.string(),
  text: z.string(),
  kind: memoryKindSchema,
  pinned: z.boolean(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type Memory = z.infer<typeof memorySchema>;

export const memoryListSchema = z.object({
  enabled: z.boolean(),
  chatRecall: z.boolean(),
  total: z.number(),
  max: z.number(),
  items: z.array(memorySchema),
});
export type MemoryList = z.infer<typeof memoryListSchema>;

export const memorySettingsSchema = z.object({
  enabled: z.boolean(),
  chatRecall: z.boolean(),
  count: z.number(),
});

export const memoryDraftSchema = z.object({
  text: z
    .string()
    .trim()
    .min(MEMORY_TEXT_MIN, "Write a little more")
    .max(MEMORY_TEXT_MAX, `Keep it under ${MEMORY_TEXT_MAX} characters`),
  kind: memoryKindSchema,
});
export type MemoryDraft = z.infer<typeof memoryDraftSchema>;
