"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";

type Seed = readonly [queryKey: readonly unknown[], data: unknown];

export function FixtureQueryProvider({
  seeds = [],
  children,
}: {
  seeds?: readonly Seed[];
  children: ReactNode;
}) {
  const [client] = useState(() => {
    const created = new QueryClient({
      defaultOptions: {
        queries: { staleTime: Infinity, retry: false, refetchOnWindowFocus: false },
      },
    });
    for (const [key, data] of seeds) created.setQueryData(key, data);
    return created;
  });
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}
