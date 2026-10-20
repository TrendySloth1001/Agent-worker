import type { ReactNode } from "react";

export function RichBlock({ lang, code }: { lang: string; code: string }): ReactNode {
  void lang;
  void code;
  return null;
}

export function isRichLang(lang: string): boolean {
  void lang;
  return false;
}
