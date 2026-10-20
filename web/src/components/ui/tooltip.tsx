"use client";

import { Tooltip as TooltipPrimitive } from "radix-ui";
import type { ComponentProps, ReactNode } from "react";
import { cn } from "@/lib/cn";

export const TooltipProvider = TooltipPrimitive.Provider;

interface TooltipProps extends Omit<ComponentProps<typeof TooltipPrimitive.Content>, "content"> {
  content: ReactNode;
  children: ReactNode;
}

export function Tooltip({ content, children, className, sideOffset = 8, ...props }: TooltipProps) {
  return (
    <TooltipPrimitive.Root>
      <TooltipPrimitive.Trigger asChild>{children}</TooltipPrimitive.Trigger>
      <TooltipPrimitive.Portal>
        <TooltipPrimitive.Content
          sideOffset={sideOffset}
          className={cn(
            "z-50 rounded-md bg-text-primary px-md py-xs font-mono text-caption tracking-[0.04em] text-text-inverse",
            "animate-pop",
            className,
          )}
          {...props}
        >
          {content}
        </TooltipPrimitive.Content>
      </TooltipPrimitive.Portal>
    </TooltipPrimitive.Root>
  );
}
