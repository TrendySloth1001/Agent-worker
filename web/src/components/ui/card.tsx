import type { ComponentProps } from "react";
import { cn } from "@/lib/cn";

export interface CardProps extends ComponentProps<"div"> {
  raised?: boolean;
  bordered?: boolean;
}

export function Card({ raised = false, bordered = true, className, ...props }: CardProps) {
  return (
    <div
      className={cn(
        "rounded-card p-lg",
        raised ? "bg-surface-raised" : "bg-surface",
        bordered && "border border-border",
        className,
      )}
      {...props}
    />
  );
}
