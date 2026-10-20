import { z } from "zod";
import { looseJson } from "../lib/text";

const INTENT_ACTIONS = [
  "view",
  "dial",
  "sendto",
  "send",
  "set_alarm",
  "set_timer",
  "insert_event",
  "insert_contact",
  "launch",
] as const;
export type IntentAction = (typeof INTENT_ACTIONS)[number];

const intentSchema = z.object({
  action: z.enum(INTENT_ACTIONS),
  uri: z.string().max(2000).optional(),
  package: z.string().max(200).optional(),
  fallback: z.string().max(2000).optional(),
  chooser: z.boolean().optional(),
  extras: z.record(z.string(), z.union([z.string(), z.number(), z.boolean()])).optional(),
});
export type CardIntent = z.infer<typeof intentSchema>;

const cardSchema = z.object({
  v: z.literal(1),
  type: z.enum(["place", "event", "clock", "contact", "product", "ride", "food", "travel", "upi"]),
  title: z.string().trim().min(1).max(200),
  subtitle: z.string().max(300).optional(),
  rows: z
    .array(z.object({ k: z.string().max(60), v: z.string().max(400) }))
    .max(12)
    .optional(),
  notice: z.string().max(300).optional(),
  actions: z
    .array(
      z.object({
        id: z.string().max(60),
        label: z.string().trim().min(1).max(40),
        app: z.string().max(40).default(""),
        primary: z.boolean().optional(),
        chip: z.boolean().optional(),
        group: z.literal("apps").optional(),
        intent: intentSchema,
      }),
    )
    .min(1)
    .max(12),
});
export type IntentCardData = z.infer<typeof cardSchema>;
export type CardAction = IntentCardData["actions"][number];

export function parseIntentCard(code: string): IntentCardData | null {
  const result = cardSchema.safeParse(looseJson(code));
  return result.success ? result.data : null;
}
