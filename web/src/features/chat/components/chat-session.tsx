"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { useCallback } from "react";
import { toast } from "@/components/ui/toaster";
import { CONVERSATIONS_KEY } from "@/features/history/api/use-conversations";
import { fetchStarters } from "../api/conversations";
import { useModels } from "../api/use-models";
import { CHAT_COPY } from "../lib/copy";
import type { StoredMessage } from "../schemas/message";
import { useChatStream } from "../state/use-chat-stream";
import { ChatView } from "./chat-view";

const STARTERS_STALE_MS = 10 * 60_000;

interface ChatSessionProps {
  conversationId?: string;
  initialMessages?: StoredMessage[];
  userName?: string;
  onAttach?: () => void;
}

export function ChatSession({ conversationId, initialMessages, userName, onAttach }: ChatSessionProps) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const models = useModels();
  const { data: starters } = useQuery({
    queryKey: ["starters"],
    queryFn: fetchStarters,
    staleTime: STARTERS_STALE_MS,
    enabled: !conversationId,
  });

  const onSaved = useCallback(
    (id: string, first: boolean) => {
      void queryClient.invalidateQueries({ queryKey: CONVERSATIONS_KEY });
      if (first) window.history.replaceState(null, "", `/chat/${id}`);
    },
    [queryClient],
  );
  const onSaveError = useCallback(() => toast(CHAT_COPY.saveFailed), []);

  const chat = useChatStream({ conversationId, initialMessages, onSaved, onSaveError });
  const newChat = useCallback(() => router.push("/chat"), [router]);

  return (
    <ChatView
      chat={chat}
      models={models}
      userName={userName}
      starters={starters}
      onNewChat={newChat}
      onAttach={onAttach}
    />
  );
}
