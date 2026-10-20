import type { ComponentProps } from "react";
import { cn } from "@/lib/cn";

export function Kbd({ className, ...props }: ComponentProps<"kbd">) {
  return (
    <kbd
      className={cn(
        "inline-flex min-w-6 items-center justify-center rounded-sm border border-border-strong",
        "bg-surface-raised px-xs py-xxs font-mono text-caption text-text-secondary",
        className,
      )}
      {...props}
    />
  );
}
