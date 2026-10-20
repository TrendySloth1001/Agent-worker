"use client";

import { Button } from "./button";
import { Illustration, type IllustrationName } from "./illustration";
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "./sheet";

export interface ConfirmSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onConfirm: () => void;
  illustration: IllustrationName;
  kicker: string;
  title: string;
  body?: string;
  confirmLabel: string;
  cancelLabel?: string;
  destructive?: boolean;
}

export function ConfirmSheet({
  open,
  onOpenChange,
  onConfirm,
  illustration,
  kicker,
  title,
  body,
  confirmLabel,
  cancelLabel = "Cancel",
  destructive = false,
}: ConfirmSheetProps) {
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent>
        <div className="flex flex-col gap-xl text-center">
          <div className="flex flex-col gap-lg">
            <Illustration name={illustration} height={150} />
            <div className="flex flex-col gap-sm">
              <p className="font-mono text-caption tracking-[0.1em] text-accent-text uppercase">
                {kicker}
              </p>
              <SheetTitle className="text-headline font-bold">{title}</SheetTitle>
              {body && (
                <SheetDescription className="text-body text-text-secondary">
                  {body}
                </SheetDescription>
              )}
            </div>
          </div>
          <div className="flex gap-md">
            <Button plain variant="secondary" fullWidth onClick={() => onOpenChange(false)}>
              {cancelLabel}
            </Button>
            <Button
              plain
              variant={destructive ? "danger" : "primary"}
              fullWidth
              onClick={() => {
                onConfirm();
                onOpenChange(false);
              }}
            >
              {confirmLabel}
            </Button>
          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
}
