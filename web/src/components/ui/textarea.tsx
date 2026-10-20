"use client";

import { useCallback, useLayoutEffect, useRef, type ComponentProps } from "react";
import { cn } from "@/lib/cn";
import { FIELD_CLASS } from "./input";

const MAX_HEIGHT = 240;

export function Textarea({
  className,
  onInput,
  rows = 1,
  ref,
  ...props
}: ComponentProps<"textarea">) {
  const inner = useRef<HTMLTextAreaElement | null>(null);

  const fit = useCallback(() => {
    const el = inner.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight, MAX_HEIGHT)}px`;
  }, []);

  useLayoutEffect(fit, [fit, props.value]);

  return (
    <textarea
      ref={(node) => {
        inner.current = node;
        if (typeof ref === "function") ref(node);
        else if (ref) ref.current = node;
      }}
      rows={rows}
      onInput={(e) => {
        fit();
        onInput?.(e);
      }}
      className={cn(
        FIELD_CLASS,
        "min-h-input-height resize-none rounded-field py-[14px]",
        className,
      )}
      {...props}
    />
  );
}
