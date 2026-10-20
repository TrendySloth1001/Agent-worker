"use client";

import type { ReactNode } from "react";
import { ThemeProvider } from "@/components/theme/theme-provider";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryProvider } from "@/lib/api/query-provider";

export function Providers({ children }: { children: ReactNode }) {
  return (
    <ThemeProvider>
      <QueryProvider>
        <TooltipProvider delayDuration={200}>{children}</TooltipProvider>
      </QueryProvider>
      <Toaster />
    </ThemeProvider>
  );
}
