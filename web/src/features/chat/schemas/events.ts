import { z } from "zod";
import { citationSchema, evidenceSchema, imageRefSchema } from "./message";

const suggestToggleSchema = z.discriminatedUnion("kind", [
  z.object({
    kind: z.literal("kb"),
    reason: z.string().catch(""),
    sampleTitles: z.array(z.string()).catch([]),
  }),
  z.object({
    kind: z.literal("doc"),
    reason: z.string().catch(""),
    proposedTitle: z.string().catch(""),
  }),
]);

const memoryChangeSchema = z.looseObject({
  op: z.string(),
  id: z.string().catch(""),
  text: z.string().catch(""),
});

export const EVENT_SCHEMAS = {
  start: z.object({ candidates: z.array(z.string()).catch([]) }),
  status: z.object({ phase: z.string().catch("") }),
  model: z.object({ model: z.string(), attempt: z.number().catch(1) }),
  delta: z.object({ text: z.string() }),
  reset: z.object({ reason: z.string().catch("") }),
  notice: z.object({ code: z.string().catch(""), message: z.string().catch("") }),
  tools: z.object({
    web: z.boolean().catch(false),
    webMode: z.string().optional(),
    kb: z.boolean().catch(false),
  }),
  sources: z.object({ citations: z.array(citationSchema) }),
  evidence: z.object({ items: z.array(evidenceSchema) }),
  images: z.object({ images: z.array(imageRefSchema) }),
  table: z.looseObject({
    phase: z.string().catch(""),
    elapsedMs: z.number().optional(),
    etaMs: z.number().optional(),
  }),
  suggestions: z.object({ items: z.array(z.string()) }),
  suggest_toggle: suggestToggleSchema,
  memory: z.object({ changes: z.array(memoryChangeSchema) }),
  usage: z.object({
    promptTokens: z.number().catch(0),
    completionTokens: z.number().catch(0),
  }),
  done: z.object({
    model: z.string().optional(),
    used: z.array(z.string()).catch([]),
    finishReason: z.string().optional(),
    latencyMs: z.number().optional(),
    table: z.boolean().optional(),
  }),
  error: z.object({
    error: z.object({
      code: z.string().catch("internal"),
      message: z.string().catch(""),
      retryable: z.boolean().catch(false),
    }),
  }),
} as const;

type EventSchemas = typeof EVENT_SCHEMAS;
export type ChatEventName = keyof EventSchemas;

export type ChatEvent = {
  [K in ChatEventName]: { type: K; data: z.infer<EventSchemas[K]> };
}[ChatEventName];

export type SuggestToggle = z.infer<typeof suggestToggleSchema>;
export type MemoryChange = z.infer<typeof memoryChangeSchema>;

const isEventName = (name: string): name is ChatEventName => name in EVENT_SCHEMAS;

export function parseChatEvent(name: string, raw: string): ChatEvent | null {
  if (!isEventName(name)) return null;
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    return null;
  }
  const parsed = EVENT_SCHEMAS[name].safeParse(json);
  if (!parsed.success) return null;
  return { type: name, data: parsed.data } as ChatEvent;
}
