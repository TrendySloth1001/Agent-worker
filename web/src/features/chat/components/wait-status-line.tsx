"use client";

import { useEffect, useRef, useState } from "react";
import { DotLoader } from "@/components/ui/dot-loader";
import { cn } from "@/lib/cn";
import { nextThinkingWord } from "../lib/thinking-words";
import type { WaitStep } from "../lib/wait-status";
import { ModelMark } from "./model-mark";

const CYCLE_MS = 1100;
const WORD_BEATS = 3;

interface WaitStatusLineProps {
  step: WaitStep;
  prompt?: string;
}

export function WaitStatusLine({ step, prompt }: WaitStatusLineProps) {
  const [beat, setBeat] = useState(0);
  const [word, setWord] = useState("Thinking…");
  const usedRef = useRef(new Set<string>());

  useEffect(() => {
    setWord(nextThinkingWord(prompt, usedRef.current));
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce) return;
    const timer = setInterval(() => setBeat((b) => b + 1), CYCLE_MS);
    return () => clearInterval(timer);
  }, [prompt]);

  useEffect(() => {
    if (step.kind === "think" && beat > 0 && beat % WORD_BEATS === 0) {
      setWord(nextThinkingWord(prompt, usedRef.current));
    }
  }, [beat, step.kind, prompt]);

  const text = step.kind === "think" ? word : step.text;
  const lit = step.kind === "picking" && step.modelIds.length > 0 ? beat % step.modelIds.length : -1;

  return (
    <div role="status" aria-live="polite" className="flex animate-fade items-center gap-sm">
      {step.modelIds.length === 0 ? (
        <DotLoader />
      ) : (
        step.modelIds.map((id, i) => (
          <ModelMark
            key={id}
            modelId={id}
            className={cn("duration-fast transition-opacity", lit >= 0 && i !== lit && "opacity-40")}
          />
        ))
      )}
      <span key={text} className="animate-fade font-mono text-caption tracking-[0.04em] text-text-secondary">
        {text}
      </span>
    </div>
  );
}
