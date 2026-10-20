"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { ConfirmSheet } from "@/components/ui/confirm-sheet";
import { IconButton } from "@/components/ui/icon-button";
import {
  Sheet,
  SheetClose,
  SheetContent,
  SheetDescription,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { toast } from "@/components/ui/toaster";
import { Tooltip } from "@/components/ui/tooltip";
import { Section } from "./section";

export function SurfacesSection() {
  const [confirm, setConfirm] = useState(false);
  const [danger, setDanger] = useState(false);
  return (
    <>
      <Section title="Cards">
        <div className="grid gap-md sm:grid-cols-2">
          <Card>
            <p className="text-title font-medium">Surface</p>
            <p className="text-body-small text-text-secondary">Bordered, on the page background.</p>
          </Card>
          <Card raised bordered={false}>
            <p className="text-title font-medium">Raised</p>
            <p className="text-body-small text-text-secondary">Tonal, no border.</p>
          </Card>
        </div>
      </Section>
      <Section title="Sheets">
        <div className="flex flex-wrap gap-md">
          <Sheet>
            <SheetTrigger asChild>
              <Button variant="secondary">Open sheet</Button>
            </SheetTrigger>
            <SheetContent>
              <div className="flex flex-col gap-lg">
                <SheetTitle className="text-headline font-bold">Sheet</SheetTitle>
                <SheetDescription className="text-body text-text-secondary">
                  A bottom sheet on phones, a centered dialog from md up.
                </SheetDescription>
                <SheetClose asChild>
                  <Button plain fullWidth>
                    Done
                  </Button>
                </SheetClose>
              </div>
            </SheetContent>
          </Sheet>
          <Sheet>
            <SheetTrigger asChild>
              <Button variant="secondary">Side panel</Button>
            </SheetTrigger>
            <SheetContent side="right">
              <div className="flex flex-col gap-lg">
                <SheetTitle className="text-headline font-bold">Side panel</SheetTitle>
                <SheetDescription className="text-body text-text-secondary">
                  A right panel from md up.
                </SheetDescription>
              </div>
            </SheetContent>
          </Sheet>
          <Button variant="secondary" onClick={() => setConfirm(true)}>
            Confirm
          </Button>
          <Button variant="danger" onClick={() => setDanger(true)}>
            Destructive confirm
          </Button>
        </div>
        <ConfirmSheet
          open={confirm}
          onOpenChange={setConfirm}
          onConfirm={() => toast("Confirmed")}
          illustration="think"
          kicker="Heads up"
          title="Start a new chat?"
          body="Your current chat stays in history."
          confirmLabel="Start"
        />
        <ConfirmSheet
          open={danger}
          onOpenChange={setDanger}
          onConfirm={() => toast("Deleted")}
          illustration="emptyHistory"
          kicker="Delete chat"
          title="Delete this chat?"
          body="This cannot be undone."
          confirmLabel="Delete"
          destructive
        />
      </Section>
      <Section title="Tooltip and toast">
        <div className="flex flex-wrap items-center gap-md">
          <Tooltip content="Copy to clipboard">
            <IconButton icon="copy" label="Copy" />
          </Tooltip>
          <Button variant="secondary" onClick={() => toast("Copied to clipboard")}>
            Show toast
          </Button>
        </div>
      </Section>
    </>
  );
}
