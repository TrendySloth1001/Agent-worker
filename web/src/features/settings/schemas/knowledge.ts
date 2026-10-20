import { z } from "zod";

export const sourceSchema = z.object({
  id: z.string(),
  type: z.string(),
  uri: z.string(),
  title: z.string().nullable(),
  status: z.string(),
  progress: z.object({ done: z.number(), total: z.number().nullable() }).nullable(),
  docCount: z.number(),
  chunkCount: z.number(),
  error: z.string().nullable(),
  lastIngestedAt: z.string().nullable(),
  createdAt: z.string(),
});
export type Source = z.infer<typeof sourceSchema>;

export const sourcesSchema = z.object({ sources: z.array(sourceSchema) });

export const addSourceResponseSchema = z.object({ source: sourceSchema });

export const statsSchema = z.object({
  sources: z.number(),
  documents: z.number(),
  chunks: z.number(),
});
export type KnowledgeStats = z.infer<typeof statsSchema>;

export const isSourceActive = (s: Pick<Source, "status">): boolean =>
  s.status === "queued" || s.status === "running";

export const sourceInputSchema = z.string().trim().min(1, "Paste a link").max(2000);

export const noteDraftSchema = z.object({
  title: z.string().trim().max(300),
  content: z.string().trim().min(1, "Write something").max(50_000),
});
export type NoteDraft = z.infer<typeof noteDraftSchema>;
