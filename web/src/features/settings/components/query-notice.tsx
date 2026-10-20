import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

export function LoadingRows({ rows = 3 }: { rows?: number }) {
  return (
    <div className="flex flex-col gap-group-gap" aria-busy>
      {Array.from({ length: rows }, (_, i) => (
        <Skeleton
          key={i}
          className="h-touch-target rounded-group-inner first:rounded-t-group-outer last:rounded-b-group-outer"
        />
      ))}
    </div>
  );
}

interface ErrorNoticeProps {
  message: string;
  onRetry?: () => void;
}

export function ErrorNotice({ message, onRetry }: ErrorNoticeProps) {
  return (
    <div
      role="alert"
      className="flex flex-col items-center gap-md rounded-card bg-cell px-lg py-xl text-center"
    >
      <p className="text-body-small text-text-secondary">{message}</p>
      {onRetry && (
        <Button size="sm" variant="secondary" onClick={onRetry}>
          Try again
        </Button>
      )}
    </div>
  );
}

interface EmptyNoticeProps {
  title: string;
  hint?: string;
}

export function EmptyNotice({ title, hint }: EmptyNoticeProps) {
  return (
    <div className="flex flex-col items-center gap-xs rounded-card bg-cell px-lg py-xxl text-center">
      <p className="text-body font-medium">{title}</p>
      {hint && <p className="text-body-small text-text-secondary">{hint}</p>}
    </div>
  );
}
