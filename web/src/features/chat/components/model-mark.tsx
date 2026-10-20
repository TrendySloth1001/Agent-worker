import { cn } from "@/lib/cn";

interface ModelMarkProps {
  modelId?: string;
  isError?: boolean;
  className?: string;
}

export function ModelMark({ modelId, isError = false, className }: ModelMarkProps) {
  if (!modelId) {
    return (
      <span aria-hidden className={cn("flex size-4 items-center justify-center", className)}>
        <span className={cn("size-2 rounded-full", isError ? "bg-accent" : "bg-text-primary")} />
      </span>
    );
  }
  const initial = (modelId.split("/").at(-1) ?? modelId).charAt(0).toUpperCase();
  return (
    <span
      aria-hidden
      className={cn(
        "flex size-4 items-center justify-center rounded-full border border-border-strong font-mono text-[9px] leading-none text-text-primary",
        className,
      )}
    >
      {initial}
    </span>
  );
}
