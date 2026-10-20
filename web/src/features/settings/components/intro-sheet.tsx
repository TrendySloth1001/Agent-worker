"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Illustration, type IllustrationName } from "@/components/ui/illustration";
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet";
import { cn } from "@/lib/cn";
import { INTRO_COPY, type IntroPage } from "../content/copy";

const ART: ReadonlyArray<IllustrationName> = ["hello", "think", "chat", "emptyHistory"];

interface IntroSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  pages: ReadonlyArray<IntroPage>;
  doneLabel: string;
  onDone?: () => void;
}

export function IntroSheet({ open, onOpenChange, pages, doneLabel, onDone }: IntroSheetProps) {
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent>
        {open && (
          <IntroPages
            pages={pages}
            doneLabel={doneLabel}
            onClose={() => onOpenChange(false)}
            onDone={onDone}
          />
        )}
      </SheetContent>
    </Sheet>
  );
}

interface IntroPagesProps {
  pages: ReadonlyArray<IntroPage>;
  doneLabel: string;
  onClose: () => void;
  onDone?: () => void;
}

function IntroPages({ pages, doneLabel, onClose, onDone }: IntroPagesProps) {
  const [index, setIndex] = useState(0);
  const page = pages[index];
  if (!page) return null;
  const last = index === pages.length - 1;

  return (
    <div className="flex flex-col gap-xl">
      <Illustration name={ART[index % ART.length] ?? "hello"} height={130} />
      <div className="flex flex-col gap-sm text-center">
        <p className="font-mono text-caption tracking-[0.1em] text-accent-text uppercase">
          {page.kicker}
        </p>
        <SheetTitle className="text-headline font-bold">{page.title}</SheetTitle>
        <SheetDescription className="text-body text-text-secondary">{page.body}</SheetDescription>
      </div>
      {page.points && (
        <ul className="flex flex-col gap-md">
          {page.points.map((p) => (
            <li key={p.title} className="flex flex-col rounded-menu bg-cell px-lg py-md">
              <span className="text-body font-medium">{p.title}</span>
              <span className="text-body-small text-text-secondary">{p.detail}</span>
            </li>
          ))}
        </ul>
      )}
      <div className="flex justify-center gap-sm" aria-hidden>
        {pages.map((p, i) => (
          <span
            key={p.title}
            className={cn(
              "size-[6px] rounded-full",
              i === index ? "bg-accent" : "bg-border-strong",
            )}
          />
        ))}
      </div>
      <div className="flex gap-md">
        {index === 0 ? (
          <Button plain variant="secondary" fullWidth onClick={onClose}>
            {INTRO_COPY.skip}
          </Button>
        ) : (
          <Button plain variant="secondary" fullWidth onClick={() => setIndex(index - 1)}>
            {INTRO_COPY.back}
          </Button>
        )}
        <Button
          plain
          fullWidth
          onClick={() => {
            if (!last) return setIndex(index + 1);
            onDone?.();
            onClose();
          }}
        >
          {last ? doneLabel : INTRO_COPY.next}
        </Button>
      </div>
    </div>
  );
}
