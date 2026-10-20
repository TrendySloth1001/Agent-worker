import { z } from "zod";

export const citationSchema = z.looseObject({
  id: z.string(),
  kind: z.enum(["kb", "web", "file", "conversation", "doc"]).catch("web"),
  title: z.string().catch(""),
  url: z.string().catch(""),
  snippet: z.string().catch(""),
  site: z.string().catch(""),
  sourceType: z.string().optional(),
});

export const imageRefSchema = z.looseObject({
  url: z.string(),
  sourceUrl: z.string().catch(""),
  title: z.string().catch(""),
  site: z.string().catch(""),
});

export const evidenceSchema = z.looseObject({
  tag: z.string(),
  claim: z.string().catch(""),
  quote: z.string().catch(""),
  score: z.number().catch(0),
});

export const attachmentSchema = z.looseObject({
  id: z.string(),
  name: z.string().catch(""),
  mime: z.string().catch(""),
  size: z.number().catch(0),
  kind: z.enum(["image", "document", "video", "audio"]).catch("document"),
});

export type Citation = z.infer<typeof citationSchema>;
export type ImageRef = z.infer<typeof imageRefSchema>;
export type Evidence = z.infer<typeof evidenceSchema>;
export type Attachment = z.infer<typeof attachmentSchema>;

export const SUGGESTIONS_META_KEY = "suggestions";
export const SEARCHED_META_KEY = "webAuto";

export const storedMessageSchema = z.object({
  role: z.enum(["user", "assistant", "context"]),
  content: z.string(),
  model: z.string().nullish(),
  meta: z.record(z.string(), z.unknown()).catch({}),
  citations: z.array(citationSchema).catch([]),
  usedIds: z.array(z.string()).catch([]),
  images: z.array(imageRefSchema).catch([]),
  evidence: z.array(evidenceSchema).catch([]),
  attachments: z.array(attachmentSchema).catch([]),
  isError: z.boolean().catch(false),
});

export type StoredMessage = z.infer<typeof storedMessageSchema>;
