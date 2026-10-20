import { cn } from "@/lib/cn";

interface WordmarkProps {
  className?: string;
}

export function Wordmark({ className }: WordmarkProps) {
  return (
    <span
      className={cn(
        "inline-flex items-baseline leading-none font-bold tracking-[-0.04em]",
        className,
      )}
    >
      sparky
      <span aria-hidden className="ml-[0.05em] inline-block size-[0.17em] rounded-full bg-accent" />
    </span>
  );
}
