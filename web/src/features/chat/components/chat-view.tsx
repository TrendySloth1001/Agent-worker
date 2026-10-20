"use client";

import { useEffect, useRef, useState } from "react";
import { FilePreviewSheet, useAttachments, type FileInfo } from "@/features/files";
import { RichActionsProvider } from "@/features/rich";
import type { AiModel } from "../api/models";
import type { ChatController } from "../state/use-chat-stream";
import { Composer } from "./composer";
import { EmptyState } from "./empty-state";
import { MessageList, type MessageListHandle } from "./message-list";

interface ChatViewProps {
  chat: ChatController;
  models: readonly AiModel[];
  userName?: string;
  starters?: readonly string[];
  onNewChat?: () => void;
}

export function ChatView({ chat, models, userName, starters, onNewChat }: ChatViewProps) {
  const input = useRef<HTMLTextAreaElement>(null);
  const list = useRef<MessageListHandle>(null);
  const { messages, streaming, stop, send, options, setOptions } = chat;
  const empty = messages.every((m) => m.role === "context");
  const attachments = useAttachments({ conversationId: chat.conversationId });
  const [preview, setPreview] = useState<FileInfo | null>(null);

  useEffect(() => {
    input.current?.focus({ preventScroll: true });
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        onNewChat?.();
        input.current?.focus();
      } else if (e.key === "Escape" && streaming) {
        stop();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onNewChat, streaming, stop]);

  const submit = (text: string, files: FileInfo[] = []) => {
    send(
      text,
      files.map(({ id, name, mime, size, kind }) => ({ id, name, mime, size, kind })),
    );
    list.current?.scrollToBottom();
  };

  return (
    <RichActionsProvider value={{ sendMessage: submit }}>
      <div className="flex h-full min-h-0 flex-col">
        {empty ? (
          <EmptyState userName={userName} prompts={starters} onPrompt={submit} />
        ) : (
          <MessageList
            handle={list}
            messages={messages}
            models={models}
            streaming={streaming}
            onRegenerate={chat.regenerate}
            onSuggestion={submit}
            onAcceptToggle={chat.acceptToggle}
            onDismissToggle={chat.dismissToggle}
          />
        )}
        <div className="mx-auto w-full max-w-[52rem] shrink-0 px-lg pt-sm pb-lg 2xl:max-w-[60rem]">
          <Composer
            inputRef={input}
            streaming={streaming}
            options={options}
            onOptionsChange={setOptions}
            onSend={submit}
            onStop={stop}
            attachments={attachments}
            onPreview={setPreview}
          />
        </div>
        <FilePreviewSheet
          file={preview}
          open={preview !== null}
          onOpenChange={(open) => !open && setPreview(null)}
        />
      </div>
    </RichActionsProvider>
  );
}
