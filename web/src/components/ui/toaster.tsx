"use client";

import { Toaster as Sonner, toast } from "sonner";

export { toast };

export function Toaster() {
  return (
    <Sonner
      position="bottom-center"
      gap={8}
      toastOptions={{
        unstyled: true,
        classNames: {
          toast:
            "flex w-[min(24rem,calc(100vw-2rem))] items-center gap-md rounded-menu bg-text-primary px-lg py-md text-body-small text-text-inverse shadow-lg",
          title: "font-medium",
          description: "text-text-inverse/70",
          actionButton: "font-mono text-caption tracking-[0.08em] uppercase text-accent-text",
        },
      }}
    />
  );
}
