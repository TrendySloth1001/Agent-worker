"use client";

import { useState } from "react";
import { cn } from "@/lib/cn";
import { useRichActions } from "../rich-actions";
import type { QuizData } from "../parsers/playful";
import { MonoButton, RichFrame } from "./frame";

const RATINGS: ReadonlyArray<readonly [number, string]> = [
  [1, "Perfect"],
  [0.8, "Great"],
  [0.6, "Good"],
  [0.4, "Not bad"],
  [0, "Keep going"],
];

export function QuizCard({ data }: { data: QuizData }) {
  const { sendMessage } = useRichActions();
  const [step, setStep] = useState(0);
  const [picked, setPicked] = useState<number | null>(null);
  const [score, setScore] = useState(0);
  const [streak, setStreak] = useState(0);
  const [best, setBest] = useState(0);
  const total = data.questions.length;
  const question = data.questions[step];

  if (!question) {
    const ratio = score / total;
    const rating = RATINGS.find(([min]) => ratio >= min)?.[1] ?? "";
    return (
      <RichFrame label={`${data.title} - results`}>
        <div className="flex flex-col items-center gap-sm py-md text-center">
          <p className="font-mono text-display leading-none">
            {score}/{total}
          </p>
          <p className="font-mono text-label tracking-[0.12em] text-accent-text uppercase">
            {rating}
          </p>
          <p className="font-mono text-caption tracking-[0.08em] text-text-tertiary uppercase">
            Best streak {best}
          </p>
          <div className="mt-sm flex flex-wrap justify-center gap-sm">
            <MonoButton
              onClick={() => {
                setStep(0);
                setPicked(null);
                setScore(0);
                setStreak(0);
                setBest(0);
              }}
            >
              Restart
            </MonoButton>
            {sendMessage && (
              <>
                <MonoButton
                  onClick={() => sendMessage(`I scored ${score}/${total} on ${data.title}`)}
                >
                  Send score
                </MonoButton>
                <MonoButton onClick={() => sendMessage(`Give me a harder quiz on ${data.title}`)}>
                  Ask for harder
                </MonoButton>
              </>
            )}
          </div>
        </div>
      </RichFrame>
    );
  }

  function choose(index: number) {
    if (picked !== null || !question) return;
    setPicked(index);
    if (index === question.answer) {
      setScore((value) => value + 1);
      setStreak((value) => {
        setBest((b) => Math.max(b, value + 1));
        return value + 1;
      });
    } else setStreak(0);
  }

  return (
    <RichFrame
      label={data.title}
      trailing={
        <span className="font-mono text-caption tracking-[0.08em] text-text-tertiary uppercase">
          Q {step + 1}/{total}
          {streak > 1 ? ` · streak ${streak}` : ""}
        </span>
      }
    >
      <p className="mb-md text-body font-medium">{question.q}</p>
      <div className="flex flex-col gap-sm">
        {question.options.map((option, index) => {
          const right = picked !== null && index === question.answer;
          const wrong = picked === index && index !== question.answer;
          return (
            <button
              key={index}
              type="button"
              disabled={picked !== null}
              onClick={() => choose(index)}
              className={cn(
                "min-h-11 rounded-md border px-md py-sm text-left text-body-small",
                "duration-fast transition-colors ease-standard focus-visible:outline-2 focus-visible:outline-accent",
                picked === null && "border-border hover:border-text-primary",
                right && "border-text-primary bg-surface-raised font-medium",
                wrong && "border-accent text-accent-text",
                picked !== null && !right && !wrong && "border-border text-text-tertiary",
              )}
            >
              {option}
            </button>
          );
        })}
      </div>
      {picked !== null && (
        <div className="mt-md flex flex-col gap-sm">
          <p className="font-mono text-caption tracking-[0.08em] uppercase">
            <span className={picked === question.answer ? "text-text-primary" : "text-accent-text"}>
              {picked === question.answer ? "Correct" : "Not quite"}
            </span>
          </p>
          {question.why && <p className="text-body-small text-text-secondary">{question.why}</p>}
          <MonoButton
            className="self-end"
            onClick={() => {
              setStep((value) => value + 1);
              setPicked(null);
            }}
          >
            {step + 1 === total ? "Results" : "Next"}
          </MonoButton>
        </div>
      )}
    </RichFrame>
  );
}
