import { z } from "zod";

export const fileInfoSchema = z.object({
  id: z.string(),
  name: z.string(),
  mime: z.string(),
  size: z.number(),
  kind: z.enum(["image", "document", "video", "audio"]),
  status: z.enum(["processing", "ready", "failed"]),
  error: z.string().nullable().optional(),
  url: z.string().optional(),
  thumbUrl: z.string().nullable().optional(),
  meta: z.record(z.string(), z.unknown()).default({}),
  createdAt: z.string().optional(),
});
export type FileInfo = z.infer<typeof fileInfoSchema>;

export const uploadResponseSchema = z.object({ file: fileInfoSchema });

export const textPageSchema = z.object({
  text: z.string(),
  offset: z.number(),
  truncated: z.boolean(),
  chars: z.number(),
});
export type TextPage = z.infer<typeof textPageSchema>;

const insightSchema = z.object({
  summary: z.string(),
  keyPoints: z.array(z.string()).default([]),
  caption: z.string().optional(),
  ocr: z.string().optional(),
});

const videoSchema = z.object({
  durationS: z.number(),
  frames: z.array(z.object({ t: z.number(), caption: z.string().optional() })).default([]),
  segments: z.array(z.object({ start: z.number(), end: z.number(), text: z.string() })).default([]),
});

export const insightPayloadSchema = z.object({
  id: z.string(),
  kind: z.enum(["image", "document", "video", "audio"]),
  status: z.enum(["processing", "ready", "failed"]),
  chars: z.number(),
  hasText: z.boolean(),
  insight: insightSchema.nullable(),
  video: videoSchema.nullable(),
});
export type InsightPayload = z.infer<typeof insightPayloadSchema>;
