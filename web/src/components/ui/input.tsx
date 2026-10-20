import type { ComponentProps } from "react";
import { cn } from "@/lib/cn";

export const FIELD_CLASS = cn(
  "w-full border border-transparent bg-field px-lg text-body text-text-primary",
  "placeholder:text-text-tertiary",
  "transition-colors duration-fast ease-standard",
  "focus-visible:border-accent focus-visible:outline-none",
  "disabled:cursor-not-allowed disabled:text-text-tertiary",
  "aria-invalid:border-error",
);

export function Input({ className, type = "text", ...props }: ComponentProps<"input">) {
  return (
    <input
      type={type}
      className={cn(FIELD_CLASS, "h-input-height rounded-pill", className)}
      {...props}
    />
  );
}
