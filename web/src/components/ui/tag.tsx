import type { ComponentProps } from "react";
import { cn } from "@/lib/cn";

export interface TagProps extends ComponentProps<"span"> {
  accent?: boolean;
  mono?: boolean;
}

export function Tag({ accent = false, mono = true, className, ...props }: TagProps) {
  return (
    <span
      className={cn(
        "inline-flex min-h-chip-height items-center rounded-pill px-sm whitespace-nowrap",
        mono ? "font-mono text-caption tracking-[0.06em] uppercase" : "text-label font-medium",
        accent ? "bg-accent/12 text-accent-text" : "bg-surface-high text-text-secondary",
        className,
      )}
      {...props}
    />
  );
}
