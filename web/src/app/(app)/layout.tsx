import type { ReactNode } from "react";
import { AppShell } from "./_components/app-shell";
import { EnsureQueryClient } from "./_components/ensure-query-client";

export default function AppLayout({ children }: { children: ReactNode }) {
  return (
    <EnsureQueryClient>
      <AppShell>{children}</AppShell>
    </EnsureQueryClient>
  );
}
