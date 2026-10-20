import { cn } from "@/lib/cn";

interface PromptChipProps {
  label: string;
  onPick: (text: string) => void;
  className?: string;
}

export function PromptChip({ label, onPick, className }: PromptChipProps) {
  return (
    <button
      type="button"
      onClick={() => onPick(label)}
      className={cn(
        "rounded-pill border border-border-strong px-lg py-sm text-left text-body-small text-text-primary",
        "duration-fast transition-[border-color,transform] ease-standard hover:border-text-primary active:scale-[0.98]",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent",
        className,
      )}
    >
      {label}
    </button>
  );
}

interface SuggestionChipsProps {
  items: readonly string[];
  onPick: (text: string) => void;
}

export function SuggestionChips({ items, onPick }: SuggestionChipsProps) {
  if (items.length === 0) return null;
  return (
    <div className="flex flex-wrap gap-sm" role="group" aria-label="Follow-up suggestions">
      {items.map((item) => (
        <PromptChip key={item} label={item} onPick={onPick} />
      ))}
    </div>
  );
}
