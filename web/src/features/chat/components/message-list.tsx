"use client";

import { useCallback, useEffect, useImperativeHandle, useRef, useState, type Ref } from "react";
import { IconButton } from "@/components/ui/icon-button";
import type { AiModel } from "../api/models";
import { CHAT_COPY } from "../lib/copy";
import type { UiMessage } from "../state/types";
import { AssistantMessage, UserBubble } from "./message-bubble";

const NEAR_BOTTOM_PX = 96;

export interface MessageListHandle {
  scrollToBottom: (smooth?: boolean) => void;
}

interface MessageListProps {
  messages: readonly UiMessage[];
  models: readonly AiModel[];
  streaming: boolean;
  onRegenerate: () => void;
  onSuggestion: (text: string) => void;
  onAcceptToggle: (id: string, kind: "kb" | "doc") => void;
  onDismissToggle: (id: string) => void;
  handle?: Ref<MessageListHandle>;
}

export function MessageList({
  messages,
  models,
  streaming,
  onRegenerate,
  onSuggestion,
  onAcceptToggle,
  onDismissToggle,
  handle,
}: MessageListProps) {
  const scroller = useRef<HTMLDivElement>(null);
  const stuck = useRef(true);
  const [away, setAway] = useState(false);

  const scrollToBottom = useCallback((smooth = false) => {
    const el = scroller.current;
    if (!el) return;
    stuck.current = true;
    el.scrollTo({ top: el.scrollHeight, behavior: smooth ? "smooth" : "auto" });
  }, []);

  useImperativeHandle(handle, () => ({ scrollToBottom }), [scrollToBottom]);

  const onScroll = () => {
    const el = scroller.current;
    if (!el) return;
    const near = el.scrollHeight - el.scrollTop - el.clientHeight < NEAR_BOTTOM_PX;
    stuck.current = near;
    setAway(!near);
  };

  useEffect(() => {
    if (stuck.current) scrollToBottom();
  }, [messages, scrollToBottom]);

  const visible = messages.filter((m) => m.role !== "context");
  const lastAssistant = visible.findLast((m) => m.role === "assistant");

  return (
    <div className="relative min-h-0 flex-1">
      <div ref={scroller} onScroll={onScroll} className="h-full overflow-y-auto overscroll-contain">
        <div className="mx-auto flex w-full max-w-[52rem] flex-col gap-xl px-lg py-xl 2xl:max-w-[60rem]">
          {visible.map((m, i) => {
            if (m.role === "user") return <UserBubble key={m.id} message={m} />;
            const prompt = visible.slice(0, i).findLast((x) => x.role === "user")?.content;
            return (
              <AssistantMessage
                key={m.id}
                message={m}
                models={models}
                prompt={prompt}
                isLast={m === lastAssistant}
                disabled={streaming}
                onRegenerate={onRegenerate}
                onSuggestion={onSuggestion}
                onAcceptToggle={onAcceptToggle}
                onDismissToggle={onDismissToggle}
              />
            );
          })}
        </div>
      </div>
      {away && (
        <div className="pointer-events-none absolute inset-x-0 bottom-md flex justify-center">
          <IconButton
            icon="scrollDown"
            label={CHAT_COPY.scrollDown}
            variant="outline"
            className="pointer-events-auto animate-pop bg-surface"
            onClick={() => scrollToBottom(true)}
          />
        </div>
      )}
    </div>
  );
}
