import type { CardIntent } from "../parsers/intent-card";
import { safeActionUrl, safeWebUrl } from "./safe-url";

export type IntentRun =
  | { kind: "link"; href: string }
  | { kind: "copy"; text: string }
  | { kind: "download"; filename: string; type: string; content: string };

const enc = encodeURIComponent;

function extra(intent: CardIntent, key: string): string {
  const value = intent.extras?.[key];
  return value === undefined ? "" : String(value);
}

function link(value: string | null): IntentRun | null {
  return value ? { kind: "link", href: value } : null;
}

function compactDate(local: string, allDay: boolean): string {
  const digits = local.replace(/[-:]/g, "");
  return allDay ? digits.slice(0, 8) : digits.length === 8 ? `${digits}T000000` : `${digits}00`;
}

function eventRun(intent: CardIntent): IntentRun | null {
  const title = extra(intent, "title");
  const begin = extra(intent, "begin");
  if (!title || !begin) return null;
  const allDay = intent.extras?.allDay === true;
  const end = extra(intent, "end") || begin;
  const dates = `${compactDate(begin, allDay)}/${compactDate(end, allDay)}`;
  const params = [
    "action=TEMPLATE",
    `text=${enc(title)}`,
    `dates=${dates}`,
    extra(intent, "location") && `location=${enc(extra(intent, "location"))}`,
    extra(intent, "description") && `details=${enc(extra(intent, "description"))}`,
  ].filter(Boolean);
  return link(safeWebUrl(`https://calendar.google.com/calendar/render?${params.join("&")}`));
}

function vcardEscape(value: string): string {
  return value.replace(/[\\;,]/g, (char) => `\\${char}`).replace(/\r?\n/g, "\\n");
}

function contactRun(intent: CardIntent): IntentRun | null {
  const name = extra(intent, "name");
  if (!name) return null;
  const lines = [
    "BEGIN:VCARD",
    "VERSION:3.0",
    `FN:${vcardEscape(name)}`,
    extra(intent, "phone") && `TEL:${vcardEscape(extra(intent, "phone"))}`,
    extra(intent, "email") && `EMAIL:${vcardEscape(extra(intent, "email"))}`,
    "END:VCARD",
  ].filter(Boolean);
  return {
    kind: "download",
    filename: `${name.replace(/[^\w.-]+/g, "_")}.vcf`,
    type: "text/vcard",
    content: lines.join("\r\n"),
  };
}

function viewRun(intent: CardIntent): IntentRun | null {
  const uri = intent.uri ?? "";
  const fallback = safeWebUrl(intent.fallback);
  const navigation = /^google\.navigation:q=(.+)$/i.exec(uri);
  if (navigation?.[1]) {
    return (
      link(safeWebUrl(`https://www.google.com/maps/dir/?api=1&destination=${navigation[1]}`)) ??
      link(fallback)
    );
  }
  const geo = /^geo:([^?]*)(?:\?q=(.*))?$/i.exec(uri);
  if (geo) {
    const query = geo[2] ?? enc(geo[1] ?? "");
    return (
      link(safeWebUrl(`https://www.google.com/maps/search/?api=1&query=${query}`)) ?? link(fallback)
    );
  }
  return link(safeActionUrl(uri)) ?? link(fallback);
}

export function resolveIntent(intent: CardIntent): IntentRun | null {
  switch (intent.action) {
    case "view":
      return viewRun(intent);
    case "dial":
      return link(safeActionUrl(intent.uri));
    case "sendto": {
      const uri = intent.uri ?? "";
      const body = extra(intent, "body");
      if (/^smsto:/i.test(uri)) {
        return link(safeActionUrl(`sms:${uri.slice(6)}${body ? `?body=${enc(body)}` : ""}`));
      }
      const subject = extra(intent, "subject");
      const query = [body && `body=${enc(body)}`, subject && `subject=${enc(subject)}`]
        .filter(Boolean)
        .join("&");
      return link(safeActionUrl(query ? `${uri}${uri.includes("?") ? "&" : "?"}${query}` : uri));
    }
    case "send":
      return extra(intent, "text") ? { kind: "copy", text: extra(intent, "text") } : null;
    case "insert_event":
      return eventRun(intent);
    case "insert_contact":
      return contactRun(intent);
    case "set_alarm": {
      const hour = extra(intent, "hour").padStart(2, "0");
      const minutes = extra(intent, "minutes").padStart(2, "0");
      return {
        kind: "copy",
        text: `Alarm ${hour}:${minutes}${extra(intent, "message") ? ` - ${extra(intent, "message")}` : ""}`,
      };
    }
    case "set_timer": {
      const seconds = Number(extra(intent, "length"));
      const minutes = Number.isFinite(seconds) ? Math.round(seconds / 60) : 0;
      return {
        kind: "copy",
        text: `Timer ${minutes} min${extra(intent, "message") ? ` - ${extra(intent, "message")}` : ""}`,
      };
    }
    case "launch":
      return link(safeWebUrl(intent.fallback));
  }
}
