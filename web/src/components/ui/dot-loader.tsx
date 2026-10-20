import { cn } from "@/lib/cn";

const DELAYS = ["0ms", "160ms", "320ms"] as const;

export function DotLoader({ className }: { className?: string }) {
  return (
    <span
      role="status"
      aria-label="Loading"
      className={cn("inline-flex items-center gap-1", className)}
    >
      {DELAYS.map((delay) => (
        <span
          key={delay}
          style={{ animationDelay: delay }}
          className="size-[5px] animate-dot-blink rounded-full bg-accent"
        />
      ))}
    </span>
  );
}
