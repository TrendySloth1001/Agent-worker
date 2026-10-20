"use client";

import type { ReactNode } from "react";
import { toast } from "@/components/ui/toaster";
import { RichActionsProvider } from "@/features/rich";

export function RichFixture({ children }: { children: ReactNode }) {
  return (
    <RichActionsProvider value={{ sendMessage: (text) => toast(`Would send: ${text}`) }}>
      {children}
    </RichActionsProvider>
  );
}
