import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

interface ProfileAuraProps {
  children: ReactNode;
  size?: number;
  className?: string;
}

export function ProfileAura({ children, size = 220, className }: ProfileAuraProps) {
  return (
    <div
      style={{ width: size, height: size }}
      className={cn("relative flex items-center justify-center", className)}
    >
      <div aria-hidden className="dot-aura absolute inset-0" />
      <div className="relative">{children}</div>
    </div>
  );
}
