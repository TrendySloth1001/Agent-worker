import type { ReactNode } from "react";
import { cn } from "@/lib/cn";
import { DotMatrix } from "./dot-matrix";

interface DotBackdropProps {
  children?: ReactNode;
  matrix?: boolean;
  className?: string;
}

export function DotBackdrop({ children, matrix = false, className }: DotBackdropProps) {
  return (
    <div className={cn("relative isolate overflow-hidden", className)}>
      <div aria-hidden className="dot-grid absolute inset-0 -z-10" />
      {matrix && <DotMatrix className="-z-10" />}
      {children}
    </div>
  );
}
