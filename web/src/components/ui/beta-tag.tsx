import { Tag } from "./tag";

export function BetaTag({ className }: { className?: string }) {
  return (
    <Tag accent className={className}>
      Beta
    </Tag>
  );
}
