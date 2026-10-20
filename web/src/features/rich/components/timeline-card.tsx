"use client";

import { useState } from "react";
import { Icon } from "@/components/ui/icon";
import { cn } from "@/lib/cn";
import type { TimelineData } from "../parsers/playful";
import { RichAction, RichFrame } from "./frame";

export function TimelineCard({ data }: { data: TimelineData }) {
  const [open, setOpen] = useState<ReadonlySet<number>>(new Set());
  const expandable = data.events.some((event) => event.detail);
  const allOpen = open.size === data.events.length;

  function toggle(index: number) {
    setOpen((current) => {
      const next = new Set(current);
      if (!next.delete(index)) next.add(index);
      return next;
    });
  }

  return (
    <RichFrame
      label={data.title}
      actions={
        expandable && (
          <RichAction
            icon={allOpen ? "collapse" : "expand"}
            label={allOpen ? "Collapse" : "Expand all"}
            onRun={() => setOpen(allOpen ? new Set() : new Set(data.events.map((_, i) => i)))}
          />
        )
      }
    >
      <ol className="relative flex flex-col">
        {data.events.map((event, index) => {
          const shown = open.has(index);
          return (
            <li key={index} className="relative flex gap-md pb-md last:pb-0">
              <span
                aria-hidden
                className={cn(
                  "absolute top-3 bottom-0 left-[4px] w-px bg-border",
                  index === data.events.length - 1 && "hidden",
                )}
              />
              <span
                aria-hidden
                className="relative mt-[6px] size-[9px] shrink-0 rounded-full border border-text-primary bg-code-background"
              />
              <div className="min-w-0 flex-1">
                <button
                  type="button"
                  disabled={!event.detail}
                  onClick={() => toggle(index)}
                  aria-expanded={event.detail ? shown : undefined}
                  className="flex w-full items-start gap-md text-left"
                >
                  <span className="w-16 shrink-0 font-mono text-caption tracking-[0.04em] text-accent-text">
                    {event.when}
                  </span>
                  <span className="min-w-0 flex-1 text-body-small font-medium">{event.title}</span>
                  {event.detail && (
                    <Icon
                      name={shown ? "collapse" : "expand"}
                      size="sm"
                      className="mt-xxs text-text-tertiary"
                    />
                  )}
                </button>
                {shown && event.detail && (
                  <p className="mt-xs pl-[calc(4rem+0.75rem)] text-body-small text-text-secondary">
                    {event.detail}
                  </p>
                )}
              </div>
            </li>
          );
        })}
      </ol>
    </RichFrame>
  );
}
