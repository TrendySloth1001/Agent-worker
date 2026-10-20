"use client";

import { useQuery } from "@tanstack/react-query";
import { fetchModels, type AiModel } from "./models";

export const MODELS_KEY = ["models"] as const;
const STALE_MS = 10 * 60_000;

export function useModels(): AiModel[] {
  const { data } = useQuery({ queryKey: MODELS_KEY, queryFn: fetchModels, staleTime: STALE_MS });
  return data ?? [];
}
