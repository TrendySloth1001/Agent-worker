import { cn } from "@/lib/cn";

interface DividerProps {
  vertical?: boolean;
  className?: string;
}

export function Divider({ vertical = false, className }: DividerProps) {
  return (
    <div
      role="separator"
      aria-orientation={vertical ? "vertical" : "horizontal"}
      className={cn(
        "shrink-0 bg-border",
        vertical ? "w-px self-stretch" : "h-px w-full",
        className,
      )}
    />
  );
}
