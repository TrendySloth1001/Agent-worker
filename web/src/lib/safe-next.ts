export const DEFAULT_NEXT = "/chat";

export function safeNext(value: string | null | undefined, fallback = DEFAULT_NEXT): string {
  if (!value || !value.startsWith("/") || value.startsWith("//") || value.includes("\\")) {
    return fallback;
  }
  return value;
}
