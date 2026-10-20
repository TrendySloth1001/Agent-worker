export const RICH_LANGS = [
  "chart",
  "quiz",
  "flashcards",
  "calc",
  "timeline",
  "stats",
  "checklist",
  "compare",
  "progress",
  "tree",
  "flow",
  "email",
  "message",
  "card",
  "ask",
  "diff",
  "html",
  "mermaid",
  "sparky-card",
  "sparky-playlist",
  "sparky-action",
] as const;

export type RichLang = (typeof RICH_LANGS)[number];

export function normalizeLang(lang: string): string {
  return lang.trim().toLowerCase();
}

export function asRichLang(lang: string): RichLang | null {
  const name = normalizeLang(lang);
  return RICH_LANGS.find((candidate) => candidate === name) ?? null;
}

export function isRichLang(lang: string): boolean {
  return asRichLang(lang) !== null;
}
