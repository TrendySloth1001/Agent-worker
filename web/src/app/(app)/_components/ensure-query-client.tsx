"use client";

import { QueryClient, QueryClientContext, QueryClientProvider } from "@tanstack/react-query";
import { useContext, useState, type ReactNode } from "react";

export function EnsureQueryClient({ children }: { children: ReactNode }) {
  const inherited = useContext(QueryClientContext);
  const [fallback] = useState(() => (inherited ? null : new QueryClient()));
  if (inherited || !fallback) return children;
  return <QueryClientProvider client={fallback}>{children}</QueryClientProvider>;
}
