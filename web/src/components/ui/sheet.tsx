"use client";

import { Dialog } from "radix-ui";
import type { ComponentProps } from "react";
import { cn } from "@/lib/cn";

export const Sheet = Dialog.Root;
export const SheetTrigger = Dialog.Trigger;
export const SheetClose = Dialog.Close;
export const SheetTitle = Dialog.Title;
export const SheetDescription = Dialog.Description;

export type SheetSide = "center" | "right";

interface SheetContentProps extends ComponentProps<typeof Dialog.Content> {
  side?: SheetSide;
  handle?: boolean;
}

const POSITION: Record<SheetSide, string> = {
  center:
    "md:inset-x-auto md:bottom-auto md:top-1/2 md:left-1/2 md:w-[28rem] md:max-w-[calc(100vw-2rem)] md:-translate-x-1/2 md:-translate-y-1/2 md:rounded-sheet md:animate-sheet-pop",
  right:
    "md:inset-x-auto md:inset-y-0 md:right-0 md:w-[26rem] md:max-h-none md:rounded-t-none md:rounded-l-sheet md:animate-sheet-side",
};

export function SheetContent({
  side = "center",
  handle = true,
  className,
  children,
  ...props
}: SheetContentProps) {
  return (
    <Dialog.Portal>
      <Dialog.Overlay className="fixed inset-0 z-40 animate-fade bg-scrim" />
      <Dialog.Content
        className={cn(
          "fixed inset-x-0 bottom-0 z-50 flex max-h-[calc(90dvh/var(--ui-zoom,1))] animate-sheet-up flex-col overflow-y-auto",
          "rounded-t-sheet bg-surface pb-lg outline-none",
          "border border-border",
          POSITION[side],
          className,
        )}
        {...props}
      >
        {handle && (
          <div aria-hidden className="flex justify-center pt-md pb-sm md:hidden">
            <span className="h-1 w-sheet-handle-width rounded-pill bg-border-strong" />
          </div>
        )}
        <div className="px-lg pt-sm md:pt-xl">{children}</div>
      </Dialog.Content>
    </Dialog.Portal>
  );
}
