import type { ComponentProps } from "react";
import { cn } from "@/lib/cn";
import { Icon, type IconSize } from "./icon";
import type { IconName } from "./icons";

export type IconButtonVariant = "outline" | "ghost" | "filled";

const VARIANTS: Record<IconButtonVariant, string> = {
  outline: "border border-border-strong text-text-primary hover:border-text-primary",
  ghost: "text-text-secondary hover:bg-surface-raised hover:text-text-primary",
  filled: "bg-text-primary text-text-inverse hover:bg-accent hover:text-white",
};

export interface IconButtonProps extends Omit<ComponentProps<"button">, "children"> {
  icon: IconName;
  label: string;
  variant?: IconButtonVariant;
  iconSize?: IconSize;
}

export function IconButton({
  icon,
  label,
  variant = "outline",
  iconSize = "md",
  className,
  type = "button",
  ...props
}: IconButtonProps) {
  return (
    <button
      type={type}
      aria-label={label}
      className={cn(
        "inline-flex size-10 shrink-0 items-center justify-center rounded-full",
        "duration-fast transition-[background-color,border-color,color,transform] ease-standard",
        "active:scale-95 disabled:pointer-events-none disabled:text-text-tertiary",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent",
        VARIANTS[variant],
        className,
      )}
      {...props}
    >
      <Icon name={icon} size={iconSize} />
    </button>
  );
}
