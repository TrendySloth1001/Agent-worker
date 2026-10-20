"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import { ApiError } from "./client";

const STALE_MS = 30_000;
const MAX_RETRIES = 2;

const shouldRetry = (count: number, error: Error): boolean =>
  count < MAX_RETRIES && !(error instanceof ApiError && error.status >= 400 && error.status < 500);

export function QueryProvider({ children }: { children: ReactNode }) {
  const [client] = useState(
    () =>
      new QueryClient({
        defaultOptions: { queries: { staleTime: STALE_MS, retry: shouldRetry } },
      }),
  );
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}
