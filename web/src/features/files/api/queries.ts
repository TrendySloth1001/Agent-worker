"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { getInsight, getText, readWithSparky } from "./client";

export const fileKeys = {
  insight: (id: string) => ["files", id, "insight"] as const,
  text: (id: string) => ["files", id, "text"] as const,
};

export function useInsight(id: string, enabled = true) {
  return useQuery({ queryKey: fileKeys.insight(id), queryFn: () => getInsight(id), enabled });
}

export function useReadWithSparky(id: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: () => readWithSparky(id),
    onSuccess: (payload) => client.setQueryData(fileKeys.insight(id), payload),
  });
}

export function useExtractedText(id: string, enabled = true) {
  return useQuery({
    queryKey: fileKeys.text(id),
    queryFn: () => getText(id),
    enabled,
    retry: false,
  });
}
