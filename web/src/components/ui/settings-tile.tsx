import type { ReactNode } from "react";
import { cn } from "@/lib/cn";
import { Icon } from "./icon";
import type { IconName } from "./icons";

export interface SettingsTileProps {
  icon?: IconName;
  leading?: ReactNode;
  title: string;
  subtitle?: string;
  badge?: ReactNode;
  value?: string;
  trailing?: ReactNode;
  chevron?: boolean;
  danger?: boolean;
  onClick?: () => void;
}

export function SettingsTile({
  icon,
  leading,
  title,
  subtitle,
  badge,
  value,
  trailing,
  chevron = false,
  danger = false,
  onClick,
}: SettingsTileProps) {
  const content = (
    <>
      {leading ??
        (icon && (
          <span className="flex size-icon-circle shrink-0 items-center justify-center rounded-full bg-cell-high">
            <Icon name={icon} size="lg" className={danger ? "text-error" : "text-text-primary"} />
          </span>
        ))}
      <span className="flex min-w-0 flex-1 flex-col text-left">
        <span className="flex items-center gap-sm">
          <span className={cn("truncate text-body", danger && "text-error")}>{title}</span>
          {badge}
        </span>
        {subtitle && <span className="text-body-small text-text-secondary">{subtitle}</span>}
      </span>
      {value && <span className="shrink-0 text-body-small text-text-secondary">{value}</span>}
      {trailing}
      {chevron && <Icon name="chevronRight" size="md" className="shrink-0 text-text-tertiary" />}
    </>
  );

  const base = "flex min-h-touch-target w-full items-center gap-md px-lg py-sm";
  if (!onClick) return <div className={base}>{content}</div>;
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        base,
        "duration-fast transition-colors ease-standard hover:bg-cell-high/50 active:bg-cell-high",
        "focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent",
      )}
    >
      {content}
    </button>
  );
}
