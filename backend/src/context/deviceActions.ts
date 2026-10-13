import { z } from "zod";

/**
 * Device actions ("set an alarm for 7", "call mum", "navigate to the station").
 * Only when the client says it can run them (the Android app and its assistant
 * overlay send `deviceActions`). The model proposes an action as a fenced
 * ```sparky-action block; the app shows it as a card and runs it only after
 * the user taps Confirm. Nothing here runs anything.
 */
export const ACTION_FENCE = "sparky-action";

export const ACTION_TYPES = [
  "alarm",
  "timer",
  "reminder",
  "event",
  "app",
  "url",
  "dial",
  "sms",
  "email",
  "whatsapp",
  "share",
  "navigate",
] as const;

export const deviceActionsSchema = z.object({
  /** The phone's local time with its UTC offset, e.g. 2026-10-13T14:05:00+02:00. */
  localTime: z.string().trim().max(40).optional(),
});

export type DeviceActionsClient = z.infer<typeof deviceActionsSchema>;

/** The system message that teaches the action block, or null when the client cannot run actions. */
export function deviceActionsMessage(client: DeviceActionsClient | undefined): string | null {
  if (!client) return null;
  const time = client.localTime?.trim();
  return [
    `The user's phone can run actions you propose. When the user asks you to DO something on their phone (set an alarm or timer, remind them, add a calendar event, open an app or a web page, call or text someone, write an email or WhatsApp, share text, navigate somewhere), reply with one short sentence and a fenced \`\`\`${ACTION_FENCE} block holding one JSON object. The app shows it as a card; nothing happens until the user taps Confirm, so never say it is done.`,
    time ? `The phone's local time now: ${time}. Write times as local time (no offset).` : null,
    "Objects (only these keys; omit unknown optional ones, never invent numbers or addresses):",
    '{"type":"alarm","time":"HH:MM","label":"optional"}',
    '{"type":"timer","seconds":600,"label":"optional"}',
    '{"type":"reminder","text":"what to remind","at":"YYYY-MM-DDTHH:MM"}',
    '{"type":"event","title":"...","start":"YYYY-MM-DDTHH:MM","end":"optional, same format","allDay":false,"location":"optional","notes":"optional"}',
    '{"type":"app","name":"app name as on the phone"}',
    '{"type":"url","url":"https://..."}',
    '{"type":"dial","number":"+44 20 7946 0000"}',
    '{"type":"sms","number":"optional","body":"message text"}',
    '{"type":"email","to":"optional address","subject":"...","body":"..."}',
    '{"type":"whatsapp","number":"optional, international format","text":"..."}',
    '{"type":"share","text":"..."}',
    '{"type":"navigate","destination":"place or address","travel":"drive|walk|bike|transit (optional)"}',
    "Use at most one block per reply, only when the user asked for the action (not for questions about it). If something needed is missing (who to call, what time), ask instead of guessing. Never use the block for things the phone cannot do.",
  ]
    .filter(Boolean)
    .join("\n");
}
