"use client";

import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  deleteConversation,
  listConversations,
  pinConversation,
  renameConversation,
} from "@/features/chat/api/conversations";

export const CONVERSATIONS_KEY = ["conversations"] as const;

export function useConversations(query: string) {
  return useQuery({
    queryKey: [...CONVERSATIONS_KEY, query],
    queryFn: () => listConversations(query),
    placeholderData: keepPreviousData,
  });
}

export function useConversationActions() {
  const client = useQueryClient();
  const refresh = () => client.invalidateQueries({ queryKey: CONVERSATIONS_KEY });
  const rename = useMutation({
    mutationFn: (v: { id: string; title: string }) => renameConversation(v.id, v.title),
    onSuccess: refresh,
  });
  const pin = useMutation({
    mutationFn: (v: { id: string; pinned: boolean }) => pinConversation(v.id, v.pinned),
    onSuccess: refresh,
  });
  const remove = useMutation({
    mutationFn: (id: string) => deleteConversation(id),
    onSuccess: refresh,
  });
  return { rename, pin, remove };
}
