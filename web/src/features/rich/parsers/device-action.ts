import { z } from "zod";
import { safeActionUrl, safeWebUrl } from "../lib/safe-url";
import { looseJson } from "../lib/text";

const text = z.string().trim().max(2000);

const actionSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("alarm"), time: text, label: text.optional() }),
  z.object({ type: z.literal("timer"), seconds: z.number().positive(), label: text.optional() }),
  z.object({ type: z.literal("reminder"), text, at: text.optional() }),
  z.object({
    type: z.literal("event"),
    title: text,
    start: text,
    end: text.optional(),
    allDay: z.boolean().optional(),
    location: text.optional(),
    notes: text.optional(),
  }),
  z.object({ type: z.literal("app"), name: text }),
  z.object({ type: z.literal("url"), url: text, app: text.optional() }),
  z.object({ type: z.literal("dial"), number: text }),
  z.object({ type: z.literal("sms"), number: text.optional(), body: text }),
  z.object({
    type: z.literal("email"),
    to: text.optional(),
    subject: text.optional(),
    body: text.optional(),
  }),
  z.object({ type: z.literal("whatsapp"), number: text.optional(), text }),
  z.object({ type: z.literal("share"), text }),
  z.object({ type: z.literal("navigate"), destination: text, travel: text.optional() }),
]);
export type DeviceAction = z.infer<typeof actionSchema>;

export type DeviceActionView = {
  kicker: string;
  title: string;
  subtitle?: string;
} & (
  | { kind: "link"; href: string; cta: string }
  | { kind: "copy"; text: string; cta: string }
  | { kind: "phone" }
);

const enc = encodeURIComponent;
const TRAVEL: Record<string, string> = {
  drive: "driving",
  walk: "walking",
  bike: "bicycling",
  transit: "transit",
};

function hostOf(href: string): string {
  return new URL(href).hostname.replace(/^www\./, "");
}

function calendarDate(local: string, allDay: boolean): string {
  const digits = local.replace(/[-:]/g, "");
  return allDay ? digits.slice(0, 8) : digits.length === 8 ? `${digits}T000000` : `${digits}00`;
}

function view(action: DeviceAction): DeviceActionView | null {
  switch (action.type) {
    case "url": {
      const href = safeWebUrl(action.url);
      if (!href) return null;
      return {
        kind: "link",
        href,
        kicker: "Link",
        title: action.app ?? hostOf(href),
        subtitle: hostOf(href),
        cta: "Open",
      };
    }
    case "navigate": {
      const mode = TRAVEL[action.travel ?? ""];
      const href = `https://www.google.com/maps/dir/?api=1&destination=${enc(action.destination)}${mode ? `&travelmode=${mode}` : ""}`;
      return {
        kind: "link",
        href,
        kicker: "Directions",
        title: action.destination,
        cta: "Open in Maps",
      };
    }
    case "event": {
      const allDay = action.allDay === true;
      const dates = `${calendarDate(action.start, allDay)}/${calendarDate(action.end ?? action.start, allDay)}`;
      const params = [
        "action=TEMPLATE",
        `text=${enc(action.title)}`,
        `dates=${dates}`,
        action.location && `location=${enc(action.location)}`,
        action.notes && `details=${enc(action.notes)}`,
      ].filter(Boolean);
      const href = `https://calendar.google.com/calendar/render?${params.join("&")}`;
      return {
        kind: "link",
        href,
        kicker: "Event",
        title: action.title,
        subtitle: action.start.replace("T", " "),
        cta: "Add to Calendar",
      };
    }
    case "dial": {
      const href = safeActionUrl(`tel:${action.number.replace(/[^\d+]/g, "")}`);
      return href
        ? { kind: "link", href, kicker: "Call", title: action.number, cta: "Call" }
        : null;
    }
    case "sms": {
      const href = safeActionUrl(`sms:${action.number ?? ""}?body=${enc(action.body)}`);
      return href
        ? {
            kind: "link",
            href,
            kicker: "Message",
            title: action.number ?? "Text message",
            subtitle: action.body,
            cta: "Open Messages",
          }
        : null;
    }
    case "email": {
      const query = [
        action.subject && `subject=${enc(action.subject)}`,
        action.body && `body=${enc(action.body)}`,
      ]
        .filter(Boolean)
        .join("&");
      const href = safeActionUrl(`mailto:${action.to ?? ""}${query ? `?${query}` : ""}`);
      return href
        ? {
            kind: "link",
            href,
            kicker: "Email",
            title: action.subject ?? action.to ?? "New email",
            subtitle: action.to,
            cta: "Open Mail",
          }
        : null;
    }
    case "whatsapp": {
      const number = (action.number ?? "").replace(/\D/g, "");
      const href = `https://wa.me/${number}?text=${enc(action.text)}`;
      return {
        kind: "link",
        href,
        kicker: "WhatsApp",
        title: action.number ?? "WhatsApp message",
        subtitle: action.text,
        cta: "Open WhatsApp",
      };
    }
    case "share":
      return { kind: "copy", text: action.text, kicker: "Share", title: action.text, cta: "Copy" };
    case "alarm":
      return { kind: "phone", kicker: "Alarm", title: action.time, subtitle: action.label };
    case "timer":
      return {
        kind: "phone",
        kicker: "Timer",
        title: `${Math.round(action.seconds / 60)} min`,
        subtitle: action.label,
      };
    case "reminder":
      return {
        kind: "phone",
        kicker: "Reminder",
        title: action.text,
        subtitle: action.at?.replace("T", " "),
      };
    case "app":
      return { kind: "phone", kicker: "App", title: action.name };
  }
}

export function parseDeviceAction(code: string): DeviceActionView | null {
  const parsed = actionSchema.safeParse(looseJson(code));
  return parsed.success ? view(parsed.data) : null;
}
