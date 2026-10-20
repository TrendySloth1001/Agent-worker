"use client";

import { Switch as SwitchPrimitive } from "radix-ui";
import type { ComponentProps } from "react";
import { cn } from "@/lib/cn";

export function Switch({ className, ...props }: ComponentProps<typeof SwitchPrimitive.Root>) {
  return (
    <SwitchPrimitive.Root
      className={cn(
        "relative inline-flex h-toggle-height w-toggle-width shrink-0 items-center rounded-pill border p-xs",
        "duration-fast border-border-strong transition-colors ease-standard",
        "data-[state=checked]:border-accent data-[state=checked]:bg-accent",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent",
        "disabled:opacity-50",
        className,
      )}
      {...props}
    >
      <SwitchPrimitive.Thumb
        className={cn(
          "block size-toggle-knob rounded-full bg-text-tertiary",
          "duration-fast transition-[transform,background-color] ease-standard",
          "data-[state=checked]:translate-x-[18px] data-[state=checked]:bg-white",
        )}
      />
    </SwitchPrimitive.Root>
  );
}
