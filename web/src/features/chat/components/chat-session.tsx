"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect } from "react";
import { toast } from "@/components/ui/toaster";
import { CONVERSATIONS_KEY } from "@/features/history/api/use-conversations";
import { QUICK_ASK_PARAM, takeQuickAsk } from "@/features/quick-ask";
import { useMe } from "@/lib/api/use-me";
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
}

export function ChatSession({ conversationId, initialMessages, userName }: ChatSessionProps) {
  const router = useRouter();
  const params = useSearchParams();
  const me = useMe();
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
  const { send } = chat;
  const quick = !conversationId && params.get(QUICK_ASK_PARAM) === "1";
  useEffect(() => {
    if (!quick) return;
    const prompt = takeQuickAsk();
    window.history.replaceState(null, "", "/chat");
    if (prompt) send(prompt);
  }, [quick, send]);

  const newChat = useCallback(() => router.push("/chat"), [router]);

  return (
    <ChatView
      chat={chat}
      models={models}
      userName={userName ?? me.data?.user.name}
      starters={starters}
      onNewChat={newChat}
    />
  );
}
