import { cn } from "@/lib/cn";

interface SpinnerProps {
  size?: number;
  className?: string;
}

export function Spinner({ size = 22, className }: SpinnerProps) {
  return (
    <span
      role="status"
      aria-label="Loading"
      style={{ width: size, height: size }}
      className={cn(
        "inline-block animate-spin rounded-full border-[1.5px] border-accent border-t-transparent",
        className,
      )}
    />
  );
}
