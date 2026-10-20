"use client";

import { useQuery } from "@tanstack/react-query";
import { authApi } from "./client";
import { meSchema, type Me } from "./schemas";

export const ME_KEY = ["me"] as const;

export function useMe() {
  return useQuery<Me>({
    queryKey: ME_KEY,
    queryFn: ({ signal }) => authApi.get("/me", meSchema, { signal }),
  });
}
