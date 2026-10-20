"use client";

import { useState } from "react";
import { Icon } from "@/components/ui/icon";
import { cn } from "@/lib/cn";
import { useRichActions } from "../rich-actions";
import type { ChecklistData } from "../parsers/playful";
import { RichAction, RichFrame } from "./frame";

export function ChecklistCard({ data }: { data: ChecklistData }) {
  const { sendMessage } = useRichActions();
  const [done, setDone] = useState<boolean[]>(() => data.items.map((item) => item.done));
  const finished = done.filter(Boolean).length;
  const left = data.items.filter((_, i) => !done[i]).map((item) => item.text);

  function progress(): string {
    return left.length === 0
      ? `Finished all ${data.items.length} items on "${data.title}".`
      : `Progress on "${data.title}": ${finished}/${data.items.length} done. Still to do: ${left.join(", ")}.`;
  }

  return (
    <RichFrame
      label={data.title}
      trailing={
        <span className="font-mono text-caption tracking-[0.08em] text-text-tertiary uppercase">
          {finished === data.items.length ? "All done" : `${finished}/${data.items.length}`}
        </span>
      }
      actions={
        sendMessage && (
          <RichAction
            icon="send"
            label="Send progress"
            doneLabel="Sent"
            onRun={() => sendMessage(progress())}
          />
        )
      }
    >
      <div className="mb-md h-0.5 overflow-hidden rounded-pill bg-border">
        <div
          className="duration-normal h-full bg-accent transition-[width] ease-standard"
          style={{ width: `${(finished / data.items.length) * 100}%` }}
        />
      </div>
      <ul className="flex flex-col">
        {data.items.map((item, index) => (
          <li key={index}>
            <button
              type="button"
              role="checkbox"
              aria-checked={done[index]}
              onClick={() =>
                setDone((current) => current.map((value, i) => (i === index ? !value : value)))
              }
              className="flex min-h-9 w-full items-start gap-md py-xs text-left focus-visible:outline-2 focus-visible:outline-accent"
            >
              <span
                className={cn(
                  "mt-xxs flex size-[18px] shrink-0 items-center justify-center rounded-sm border",
                  done[index]
                    ? "border-text-primary bg-text-primary text-text-inverse"
                    : "border-border-strong",
                )}
              >
                {done[index] && <Icon name="check" size="xs" />}
              </span>
              <span
                className={cn("text-body-small", done[index] && "text-text-tertiary line-through")}
              >
                {item.text}
              </span>
            </button>
          </li>
        ))}
      </ul>
    </RichFrame>
  );
}
