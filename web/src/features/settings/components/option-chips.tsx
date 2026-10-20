"use client";

import { RadioGroup } from "radix-ui";
import { cn } from "@/lib/cn";

export interface ChipOption<T extends string> {
  value: T;
  label: string;
}

interface OptionChipsProps<T extends string> {
  label: string;
  value: T;
  options: ReadonlyArray<ChipOption<T>>;
  onChange: (value: T) => void;
}

export function OptionChips<T extends string>({
  label,
  value,
  options,
  onChange,
}: OptionChipsProps<T>) {
  return (
    <RadioGroup.Root
      aria-label={label}
      value={value}
      onValueChange={(v) => {
        const match = options.find((o) => o.value === v);
        if (match) onChange(match.value);
      }}
      className="flex flex-wrap gap-sm"
    >
      {options.map((o) => (
        <RadioGroup.Item
          key={o.value}
          value={o.value}
          className={cn(
            "inline-flex h-segment-height items-center rounded-pill border px-lg text-body-small",
            "duration-fast transition-colors ease-standard",
            "border-border-strong text-text-secondary hover:text-text-primary",
            "data-[state=checked]:border-text-primary data-[state=checked]:bg-text-primary data-[state=checked]:text-text-inverse",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent",
          )}
        >
          {o.label}
        </RadioGroup.Item>
      ))}
    </RadioGroup.Root>
  );
}
