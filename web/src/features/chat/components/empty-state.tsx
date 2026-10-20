"use client";

import { useState, useSyncExternalStore } from "react";
import { DotBackdrop } from "@/components/brand/dot-backdrop";
import { Illustration } from "@/components/ui/illustration";
import { EMPTY_PROMPTS } from "../lib/copy";
import { greetingOptions, type Greeting } from "../lib/greetings";
import { PromptChip } from "./suggestion-chips";

const subscribeNever = (): (() => void) => () => undefined;

interface EmptyStateProps {
  userName?: string;
  prompts?: readonly string[];
  onPrompt: (text: string) => void;
}

export function EmptyState({ userName, prompts, onPrompt }: EmptyStateProps) {
  const mounted = useSyncExternalStore(subscribeNever, () => true, () => false);
  const [greeting] = useState<Greeting | undefined>(() => {
    const options = greetingOptions(userName, new Date().getHours());
    return options[Math.floor(Math.random() * options.length)];
  });

  const list = prompts && prompts.length > 0 ? prompts : EMPTY_PROMPTS;

  return (
    <DotBackdrop className="flex min-h-0 flex-1 items-center justify-center px-lg">
      <div className="flex max-w-[34rem] flex-col items-center gap-lg py-xl text-center">
        <Illustration name="hello" height={150} />
        <div className="flex min-h-[4.5rem] flex-col gap-sm">
          <h1 className="text-headline font-bold tracking-[-0.02em] md:text-display">{mounted ? greeting?.title : ""}</h1>
          <p className="text-body-small text-text-secondary">{mounted ? greeting?.subtitle : ""}</p>
        </div>
        <div className="flex flex-wrap justify-center gap-sm">
          {list.map((p) => (
            <PromptChip key={p} label={p} onPick={onPrompt} />
          ))}
        </div>
      </div>
    </DotBackdrop>
  );
}
