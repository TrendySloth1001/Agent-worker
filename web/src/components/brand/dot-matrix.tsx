"use client";

import { useEffect, useRef } from "react";
import { useTheme } from "@/components/theme/theme-provider";
import { DotMatrixEngine } from "@/lib/dot-matrix-engine";
import { cn } from "@/lib/cn";

interface DotMatrixProps {
  interactive?: boolean;
  className?: string;
}

export function DotMatrix({ interactive = true, className }: DotMatrixProps) {
  const hostRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const engineRef = useRef<DotMatrixEngine | null>(null);
  const { resolved } = useTheme();
  const resolvedRef = useRef(resolved);

  useEffect(() => {
    resolvedRef.current = resolved;
    engineRef.current?.refreshTheme();
  }, [resolved]);

  useEffect(() => {
    const host = hostRef.current;
    const canvas = canvasRef.current;
    if (!host || !canvas) return;
    const engine = new DotMatrixEngine(canvas, host, {
      interactive,
      isDark: () => resolvedRef.current === "dark",
    });
    engineRef.current = engine;
    return () => {
      engine.dispose();
      engineRef.current = null;
    };
  }, [interactive]);

  return (
    <div ref={hostRef} className={cn("absolute inset-0", className)}>
      <canvas ref={canvasRef} aria-hidden className="block size-full" />
    </div>
  );
}
