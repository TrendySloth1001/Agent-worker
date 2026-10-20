import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

export function SettingsGroupHeader({ children }: { children: ReactNode }) {
  return <h2 className="px-lg pt-xl pb-sm text-label font-medium text-accent-text">{children}</h2>;
}

interface SettingsGroupProps {
  children: ReactNode;
  className?: string;
}

export function SettingsGroup({ children, className }: SettingsGroupProps) {
  return (
    <div
      className={cn(
        "flex flex-col gap-group-gap",
        "*:overflow-hidden *:rounded-group-inner *:bg-cell",
        "*:first:rounded-t-group-outer *:last:rounded-b-group-outer",
        className,
      )}
    >
      {children}
    </div>
  );
}
