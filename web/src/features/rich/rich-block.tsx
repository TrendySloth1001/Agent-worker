"use client";

import type { ReactNode } from "react";
import { CodeFallback } from "./components/frame";
import { renderRich } from "./registry";

export function RichBlock({ lang, code }: { lang: string; code: string }): ReactNode {
  return renderRich(lang, code) ?? <CodeFallback code={code} lang={lang} />;
}
