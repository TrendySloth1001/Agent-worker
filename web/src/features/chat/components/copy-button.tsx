"use client";

import { useEffect, useRef, useState } from "react";
import { Icon } from "@/components/ui/icon";
import { cn } from "@/lib/cn";
import { CHAT_COPY } from "../lib/copy";

const RESET_MS = 1600;

export function useCopy(text: string): { copied: boolean; copy: () => void } {
  const [copied, setCopied] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => () => void (timer.current && clearTimeout(timer.current)), []);

  const copy = () => {
    void navigator.clipboard
      .writeText(text)
      .then(() => {
        setCopied(true);
        if (timer.current) clearTimeout(timer.current);
        timer.current = setTimeout(() => setCopied(false), RESET_MS);
      })
      .catch(() => setCopied(false));
  };
  return { copied, copy };
}

export function CopyButton({ text, className }: { text: string; className?: string }) {
  const { copied, copy } = useCopy(text);
  return (
    <button
      type="button"
      onClick={copy}
      className={cn(
        "inline-flex items-center gap-xs font-mono text-caption tracking-[0.08em] text-text-tertiary uppercase",
        "duration-fast transition-colors ease-standard hover:text-text-primary",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent",
        className,
      )}
    >
      <Icon name={copied ? "check" : "copy"} size="xs" />
      <span aria-live="polite">{copied ? CHAT_COPY.copied : CHAT_COPY.copy}</span>
    </button>
  );
}
