"use client";

import { useMemo, useState } from "react";
import { evaluate } from "../lib/calc-eval";
import { formatNumber } from "../lib/text";
import type { CalcData } from "../parsers/playful";
import { RichFrame } from "./frame";

export function CalcCard({ data }: { data: CalcData }) {
  const initial = useMemo(
    () => Object.fromEntries(data.inputs.map((input) => [input.id, input.value])),
    [data],
  );
  const [values, setValues] = useState<Record<string, number>>(initial);

  return (
    <RichFrame
      label={data.title}
      trailing={
        <button
          type="button"
          onClick={() => setValues(initial)}
          className="font-mono text-caption tracking-[0.08em] text-text-tertiary uppercase hover:text-text-primary"
        >
          Reset
        </button>
      }
    >
      <div className="flex flex-col gap-md">
        {data.inputs.map((input) => {
          const value = values[input.id] ?? input.value;
          return (
            <div key={input.id} className="flex flex-col gap-xs">
              <div className="flex items-baseline justify-between gap-md">
                <label htmlFor={`calc-${input.id}`} className="text-body-small text-text-secondary">
                  {input.label}
                </label>
                <span className="flex items-baseline gap-xs">
                  <input
                    id={`calc-${input.id}`}
                    type="number"
                    inputMode="decimal"
                    value={value}
                    min={input.min}
                    max={input.max}
                    onChange={(event) => {
                      const next = Number(event.target.value);
                      if (Number.isFinite(next))
                        setValues((current) => ({ ...current, [input.id]: next }));
                    }}
                    className="w-24 rounded-sm bg-field px-sm py-xxs text-right font-mono text-body-small text-text-primary focus-visible:outline-2 focus-visible:outline-accent"
                  />
                  {input.suffix && (
                    <span className="font-mono text-caption text-text-tertiary">
                      {input.suffix}
                    </span>
                  )}
                </span>
              </div>
              <input
                type="range"
                aria-label={input.label}
                min={input.min}
                max={input.max}
                step={(input.max - input.min) / 200 || 1}
                value={Math.min(Math.max(value, input.min), input.max)}
                onChange={(event) =>
                  setValues((current) => ({ ...current, [input.id]: Number(event.target.value) }))
                }
                className="h-1 w-full cursor-pointer accent-accent"
              />
            </div>
          );
        })}
      </div>
      <div className="mt-lg grid gap-sm border-t border-border pt-md sm:grid-cols-2">
        {data.outputs.map((output) => {
          const result = evaluate(output.expression, values);
          return (
            <div key={output.label} className="rounded-md bg-surface px-md py-sm">
              <p className="font-mono text-caption tracking-[0.08em] text-text-tertiary uppercase">
                {output.label}
              </p>
              <p className="font-mono text-metric">
                {result === null ? "—" : formatNumber(result, output.decimals)}
                {output.suffix && (
                  <span className="ml-xs text-label text-text-secondary">{output.suffix}</span>
                )}
              </p>
            </div>
          );
        })}
      </div>
    </RichFrame>
  );
}
