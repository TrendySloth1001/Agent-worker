"use client";

import { useState } from "react";
import { cn } from "@/lib/cn";
import { splitLines } from "../lib/text";
import { CopyAction, MonoButton, RichFrame } from "./frame";

export type DiffKind = "added" | "removed" | "hunk" | "meta" | "context";

const MAX_ROWS = 300;

export function diffKind(line: string, inHunk: boolean): DiffKind {
  if (!inHunk && /^(\+\+\+ |--- |diff |index )/.test(line)) return "meta";
  if (line.startsWith("@@")) return "hunk";
  if (line.startsWith("+")) return "added";
  if (line.startsWith("-")) return "removed";
  return "context";
}

const ROW: Record<DiffKind, string> = {
  added: "bg-green-500/15",
  removed: "bg-accent/12",
  hunk: "bg-surface-raised text-text-secondary",
  meta: "text-text-tertiary",
  context: "",
};

export function DiffBlock({ code }: { code: string }) {
  const [all, setAll] = useState(false);
  const lines = splitLines(code);
  const firstHunk = lines.findIndex((line) => line.startsWith("@@"));
  const rows = lines.map((line, index) => ({
    line,
    kind: diffKind(line, firstHunk >= 0 && index > firstHunk),
  }));
  const shown = all ? rows : rows.slice(0, MAX_ROWS);
  return (
    <RichFrame label="Diff" flush actions={<CopyAction text={code} />}>
      <pre className="overflow-x-auto py-sm font-mono text-label leading-normal">
        {shown.map(({ line, kind }, index) => (
          <div key={index} className={cn("min-w-max px-md", ROW[kind])}>
            {line || " "}
          </div>
        ))}
      </pre>
      {rows.length > shown.length && (
        <div className="flex justify-center border-t border-border p-sm">
          <MonoButton onClick={() => setAll(true)}>Show all {rows.length} lines</MonoButton>
        </div>
      )}
    </RichFrame>
  );
}
