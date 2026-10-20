import { z } from "zod";
import { readKeyed, splitLines } from "../lib/text";

function splitHeaders(
  code: string,
  keys: readonly string[],
): { headers: Record<string, string>; body: string } {
  const lines = splitLines(code);
  const headers: Record<string, string> = {};
  let index = 0;
  for (; index < lines.length; index++) {
    const line = lines[index] ?? "";
    const key = keys.find((candidate) => readKeyed(line, candidate) !== null);
    if (!key) break;
    headers[key] = readKeyed(line, key) ?? "";
  }
  while (index < lines.length && !(lines[index] ?? "").trim()) index++;
  return { headers, body: lines.slice(index).join("\n").trimEnd() };
}

export function plainEmailText(body: string): string {
  return body
    .split("\n")
    .map((line) =>
      line
        .replace(/^(\s*)[-*+]\s+/, "$1• ")
        .replace(/^#{1,6}\s+/, "")
        .replace(/(\*\*|__)(.+?)\1/g, "$2")
        .replace(/`([^`]+)`/g, "$1"),
    )
    .join("\n");
}

const emailSchema = z
  .object({
    to: z.string().max(400),
    cc: z.string().max(400),
    bcc: z.string().max(400),
    subject: z.string().max(300),
    body: z.string().max(20000),
  })
  .refine((draft) => draft.to !== "" || draft.subject !== "" || draft.body !== "");
export type EmailDraft = z.infer<typeof emailSchema>;

export function parseEmail(code: string): EmailDraft | null {
  const { headers, body } = splitHeaders(code, ["to", "cc", "bcc", "subject"]);
  if (Object.keys(headers).length === 0) return null;
  const result = emailSchema.safeParse({
    to: headers.to ?? "",
    cc: headers.cc ?? "",
    bcc: headers.bcc ?? "",
    subject: headers.subject ?? "",
    body: plainEmailText(body),
  });
  return result.success ? result.data : null;
}

export function emailAsText(draft: EmailDraft): string {
  const headers: Array<[string, string]> = [
    ["To", draft.to],
    ["Cc", draft.cc],
    ["Bcc", draft.bcc],
    ["Subject", draft.subject],
  ];
  const lines = headers
    .filter(([, value]) => value !== "")
    .map(([key, value]) => `${key}: ${value}`);
  return [...lines, "", draft.body].join("\n");
}

const messageSchema = z.object({
  to: z.string().max(200),
  platform: z.string().max(30),
  text: z.string().trim().min(1).max(10000),
});
export type MessageDraft = z.infer<typeof messageSchema>;

export function parseMessage(code: string): MessageDraft | null {
  const { headers, body } = splitHeaders(code, ["to", "platform"]);
  const result = messageSchema.safeParse({
    to: headers.to ?? "",
    platform: (headers.platform ?? "").toLowerCase(),
    text: body,
  });
  return result.success ? result.data : null;
}

const specSchema = z.object({
  title: z.string().trim().min(1).max(160),
  subtitle: z.string().max(240),
  rows: z
    .array(z.object({ key: z.string().min(1).max(60), value: z.string().min(1).max(400) }))
    .max(30),
});
export type SpecData = z.infer<typeof specSchema>;

export function parseSpec(code: string): SpecData | null {
  let title = "";
  let subtitle = "";
  const rows: Array<{ key: string; value: string }> = [];
  for (const line of splitLines(code)) {
    const at = line.indexOf(":");
    if (at <= 0) continue;
    const key = line.slice(0, at).trim();
    const value = line.slice(at + 1).trim();
    switch (key.toLowerCase()) {
      case "title":
        title = value;
        break;
      case "subtitle":
        subtitle = value;
        break;
      case "icon":
        break;
      default:
        if (key && value) rows.push({ key, value });
    }
  }
  const result = specSchema.safeParse({ title, subtitle, rows });
  return result.success ? result.data : null;
}

const askSchema = z.object({
  question: z.string().trim().min(1).max(400),
  options: z.array(z.string().trim().min(1).max(200)).min(2).max(6),
  multi: z.boolean(),
  other: z.boolean(),
});
export type AskData = z.infer<typeof askSchema>;

export function parseAsk(code: string): AskData | null {
  let question = "";
  let multi = false;
  let other = false;
  const options: string[] = [];
  for (const line of splitLines(code)) {
    const q = readKeyed(line, "question");
    const m = readKeyed(line, "multi");
    const o = readKeyed(line, "other");
    if (q !== null) question = q;
    else if (m !== null) multi = m.toLowerCase() === "true";
    else if (o !== null) other = o.toLowerCase() === "true";
    else if (/^\s*[-*]\s+\S/.test(line)) options.push(line.replace(/^\s*[-*]\s+/, "").trim());
  }
  const result = askSchema.safeParse({ question, options, multi, other });
  return result.success ? result.data : null;
}
