"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { getConversation } from "../api/conversations";
import { CHAT_COPY } from "../lib/copy";
import { ChatSession } from "./chat-session";

export function ConversationScreen({ id }: { id: string }) {
  const { data, isError } = useQuery({
    queryKey: ["conversation", id],
    queryFn: () => getConversation(id),
    gcTime: 0,
    refetchOnMount: "always",
    refetchOnWindowFocus: false,
    retry: false,
  });

  if (isError) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-lg px-lg text-center">
        <p className="text-body text-text-secondary">{CHAT_COPY.loadFailed}</p>
        <Button asChild plain>
          <Link href="/chat">New chat</Link>
        </Button>
      </div>
    );
  }

  if (!data) {
    return (
      <div
        className="mx-auto flex max-w-[52rem] flex-col gap-xl px-lg py-xl 2xl:max-w-[60rem]"
        aria-busy
      >
        <Skeleton className="ml-auto h-12 w-2/3" />
        <Skeleton className="h-24 w-full" />
        <Skeleton className="ml-auto h-12 w-1/2" />
      </div>
    );
  }

  return <ChatSession key={id} conversationId={id} initialMessages={data.messages} />;
}
