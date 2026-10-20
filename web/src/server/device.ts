import "server-only";

const PREFIX = "sparky web";
const MAX_LENGTH = 80;

const BROWSERS: [RegExp, string][] = [
  [/edg\//i, "Edge"],
  [/opr\/|opera/i, "Opera"],
  [/firefox\//i, "Firefox"],
  [/chrome\/|crios\//i, "Chrome"],
  [/safari\//i, "Safari"],
];

const SYSTEMS: [RegExp, string][] = [
  [/android/i, "Android"],
  [/iphone|ipad|ios/i, "iOS"],
  [/windows/i, "Windows"],
  [/mac os x|macintosh/i, "macOS"],
  [/linux|x11/i, "Linux"],
];

const firstMatch = (table: [RegExp, string][], ua: string) =>
  table.find(([pattern]) => pattern.test(ua))?.[1];

export function deviceLabel(userAgent: string | null): string {
  const ua = userAgent ?? "";
  const detail = [firstMatch(BROWSERS, ua), firstMatch(SYSTEMS, ua)].filter(Boolean).join(" on ");
  return (detail ? `${PREFIX} · ${detail}` : PREFIX).slice(0, MAX_LENGTH);
}
