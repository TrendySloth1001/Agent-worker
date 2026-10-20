"use client";

import type { ReactNode } from "react";
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet";

interface FormSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  description?: string;
  children: ReactNode;
}

export function FormSheet({ open, onOpenChange, title, description, children }: FormSheetProps) {
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent>
        <div className="flex flex-col gap-lg">
          <div className="flex flex-col gap-xs">
            <SheetTitle className="text-title font-bold">{title}</SheetTitle>
            {description ? (
              <SheetDescription className="text-body-small text-text-secondary">
                {description}
              </SheetDescription>
            ) : (
              <SheetDescription className="sr-only">{title}</SheetDescription>
            )}
          </div>
          {children}
        </div>
      </SheetContent>
    </Sheet>
  );
}

export function FieldLabel({ htmlFor, children }: { htmlFor: string; children: ReactNode }) {
  return (
    <label
      htmlFor={htmlFor}
      className="px-xs font-mono text-caption tracking-[0.08em] text-text-secondary uppercase"
    >
      {children}
    </label>
  );
}

export function FieldError({ children }: { children: ReactNode }) {
  return (
    <p role="alert" className="px-xs text-body-small text-error">
      {children}
    </p>
  );
}
