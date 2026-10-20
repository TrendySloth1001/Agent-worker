const WEB_PROTOCOLS: ReadonlySet<string> = new Set(["http:", "https:"]);
const ACTION_PROTOCOLS: ReadonlySet<string> = new Set([
  "http:",
  "https:",
  "mailto:",
  "tel:",
  "sms:",
  "upi:",
]);

function sanitize(value: string, allowed: ReadonlySet<string>): string | null {
  const trimmed = value.trim();
  if (!trimmed || /[\u0000-\u001f\u007f]/.test(trimmed)) return null;
  try {
    const url = new URL(trimmed);
    return allowed.has(url.protocol.toLowerCase()) ? url.href : null;
  } catch {
    return null;
  }
}

export function safeWebUrl(value: string | undefined | null): string | null {
  return value ? sanitize(value, WEB_PROTOCOLS) : null;
}

export function safeActionUrl(value: string | undefined | null): string | null {
  return value ? sanitize(value, ACTION_PROTOCOLS) : null;
}
