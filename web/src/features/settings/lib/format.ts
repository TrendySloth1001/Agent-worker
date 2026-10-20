export const formatCount = (n: number): string => {
  if (n >= 1_000_000) return `${trim(n / 1_000_000)}M`;
  if (n >= 1_000) return `${trim(n / 1_000)}k`;
  return String(n);
};

const trim = (n: number): string => n.toFixed(1).replace(/\.0$/, "");

export const formatLatency = (ms: number | null): string => {
  if (ms === null) return "-";
  return ms >= 1000 ? `${trim(ms / 1000)}s` : `${ms}ms`;
};

export const formatDate = (iso: string, locale = "en"): string => {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleDateString(locale, { day: "numeric", month: "short", year: "numeric" });
};

export const shortDay = (day: string): string => {
  const date = new Date(`${day}T00:00:00Z`);
  return Number.isNaN(date.getTime())
    ? day
    : date.toLocaleDateString("en", { day: "numeric", month: "short", timeZone: "UTC" });
};

export const formatContext = (tokens: number): string => formatCount(tokens);

export const displayName = (user: { name: string | null; email: string | null }): string =>
  user.name?.trim() || user.email?.split("@")[0] || "";
