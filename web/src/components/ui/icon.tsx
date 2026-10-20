import { HugeiconsIcon } from "@hugeicons/react";
import { icons, type IconName } from "./icons";

export type IconSize = "xs" | "sm" | "md" | "lg" | "xl";

const SIZES: Record<IconSize, number> = { xs: 12, sm: 16, md: 20, lg: 24, xl: 28 };
const STROKE = 1.3;

interface IconProps {
  name: IconName;
  size?: IconSize;
  className?: string;
}

export function Icon({ name, size = "md", className }: IconProps) {
  return (
    <HugeiconsIcon
      icon={icons[name]}
      size={SIZES[size]}
      strokeWidth={STROKE}
      className={className}
      aria-hidden
    />
  );
}
