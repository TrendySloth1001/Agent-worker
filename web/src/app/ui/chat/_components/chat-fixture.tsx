"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { AppShell } from "@/app/(app)/_components/app-shell";
import { MODELS_KEY } from "@/features/chat/api/use-models";
import { ChatView } from "@/features/chat/components/chat-view";
import { useChatStream } from "@/features/chat/state/use-chat-stream";
import { CONVERSATIONS_KEY } from "@/features/history/api/use-conversations";
import {
  FIXTURE_CONVERSATIONS,
  FIXTURE_MODELS,
  STORED_CONVERSATION,
  fakeStream,
  type Scenario,
} from "./fixtures";

const PROMPT = "How does SSE streaming work, and how do I parse it in the browser?";

function makeClient(): QueryClient {
  const client = new QueryClient({
    defaultOptions: { queries: { staleTime: Infinity, retry: false, refetchOnMount: false } },
  });
  client.setQueryData([...CONVERSATIONS_KEY, ""], FIXTURE_CONVERSATIONS);
  client.setQueryData(MODELS_KEY, FIXTURE_MODELS);
  return client;
}

function Fixture({ scenario }: { scenario: Scenario }) {
  const [stream] = useState(() => fakeStream(scenario === "waiting"));
  const chat = useChatStream({
    conversationId: scenario === "conversation" ? "c1" : undefined,
    initialMessages: scenario === "conversation" ? STORED_CONVERSATION : [],
    stream,
    save: () => Promise.resolve(),
  });
  const { send } = chat;

  useEffect(() => {
    if (scenario === "streaming" || scenario === "waiting") send(PROMPT);
  }, [scenario, send]);

  return (
    <ChatView
      chat={chat}
      models={FIXTURE_MODELS}
      userName="Nikhil Kumawat"
      onAttach={() => undefined}
    />
  );
}

export function ChatFixture({ scenario }: { scenario: Scenario }) {
  const [client] = useState(makeClient);
  return (
    <QueryClientProvider client={client}>
      <AppShell>
        <Fixture scenario={scenario} />
      </AppShell>
    </QueryClientProvider>
  );
}
