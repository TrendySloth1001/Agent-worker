import { Slot } from "radix-ui";
import type { ComponentProps } from "react";
import { cn } from "@/lib/cn";

export type ButtonVariant = "primary" | "secondary" | "ghost" | "danger";
export type ButtonSize = "sm" | "md" | "lg";

const VARIANTS: Record<ButtonVariant, string> = {
  primary: "bg-text-primary text-text-inverse hover:bg-accent hover:text-white",
  secondary: "border border-border-strong text-text-primary hover:border-text-primary",
  ghost: "text-text-primary hover:bg-surface-raised",
  danger: "bg-error text-white hover:opacity-90",
};

const SIZES: Record<ButtonSize, string> = {
  sm: "h-segment-height px-lg text-caption",
  md: "h-button-height px-xl text-label",
  lg: "h-14 px-xxl text-label",
};

export interface ButtonProps extends ComponentProps<"button"> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  plain?: boolean;
  fullWidth?: boolean;
  asChild?: boolean;
}

export function Button({
  variant = "primary",
  size = "md",
  plain = false,
  fullWidth = false,
  asChild = false,
  className,
  type = "button",
  ...props
}: ButtonProps) {
  const Comp = asChild ? Slot.Root : "button";
  return (
    <Comp
      type={asChild ? undefined : type}
      className={cn(
        "inline-flex shrink-0 items-center justify-center gap-sm rounded-pill font-bold whitespace-nowrap select-none",
        "duration-fast transition-[background-color,border-color,color,transform,opacity] ease-standard",
        "active:scale-[0.97] disabled:pointer-events-none disabled:bg-disabled disabled:text-text-tertiary",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent",
        plain ? "font-sans text-body font-semibold" : "font-mono tracking-[0.12em] uppercase",
        VARIANTS[variant],
        SIZES[size],
        fullWidth && "w-full",
        className,
      )}
      {...props}
    />
  );
}
