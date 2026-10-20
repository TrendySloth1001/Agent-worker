"use client";

import { useCallback, useEffect, useReducer, useRef, useState } from "react";
import {
  streamChat,
  type ChatRequest,
  type ChatStreamFn,
  type SuggestKind,
  type WebMode,
} from "../api/chat-stream";
import { saveConversation } from "../api/conversations";
import type { Attachment, StoredMessage } from "../schemas/message";
import { emptyMessage, type UiMessage } from "./types";
import {
  chatReducer,
  fromStored,
  initialChatState,
  pendingAssistant,
  toStored,
} from "./stream-reducer";

export interface ComposerOptions {
  webMode: WebMode;
  knowledge: boolean;
  roundTable: boolean;
}

export const DEFAULT_OPTIONS: ComposerOptions = {
  webMode: "auto",
  knowledge: false,
  roundTable: false,
};

export type SaveFn = (id: string, messages: StoredMessage[]) => Promise<void>;

export interface UseChatStreamOptions {
  conversationId?: string;
  initialMessages?: StoredMessage[];
  stream?: ChatStreamFn;
  save?: SaveFn;
  onSaved?: (id: string, firstSave: boolean) => void;
  onSaveError?: () => void;
}

const newId = (): string => crypto.randomUUID();

const toRequestMessages = (messages: UiMessage[]): ChatRequest["messages"] =>
  messages.flatMap((m): ChatRequest["messages"] => {
    if (m.role === "context" || m.isError || (m.role === "assistant" && m.content === ""))
      return [];
    if (m.role === "user") {
      const attachments = m.attachments.map((a) => a.id);
      return [
        {
          role: "user" as const,
          content: m.content,
          ...(attachments.length ? { attachments } : {}),
        },
      ];
    }
    return [{ role: "assistant" as const, content: m.content }];
  });

export function useChatStream({
  conversationId: initialId,
  initialMessages,
  stream = streamChat,
  save = saveConversation,
  onSaved,
  onSaveError,
}: UseChatStreamOptions = {}) {
  const [state, dispatch] = useReducer(chatReducer, initialChatState, () => ({
    messages: (initialMessages ?? []).map((m) => fromStored(m, newId())),
  }));
  const [options, setOptions] = useState<ComposerOptions>(DEFAULT_OPTIONS);
  const messagesRef = useRef(state.messages);
  const [conversationId, setConversationId] = useState(initialId);
  const idRef = useRef(initialId);
  const persistedRef = useRef(initialId !== undefined);
  const abortRef = useRef<AbortController | null>(null);
  const suppressRef = useRef<Set<SuggestKind>>(new Set());
  const optionsRef = useRef(options);
  const wasStreaming = useRef(false);

  useEffect(() => {
    messagesRef.current = state.messages;
    optionsRef.current = options;
  });

  const streaming = state.messages.some((m) => m.streaming);

  const run = useCallback(
    async (history: UiMessage[], assistantId: string) => {
      const ctl = new AbortController();
      abortRef.current = ctl;
      const opts = optionsRef.current;
      const request: ChatRequest = {
        messages: toRequestMessages(history),
        conversationId: idRef.current,
        ...opts,
        suppressSuggest: [...suppressRef.current],
      };
      let finished = false;
      try {
        for await (const event of stream(request, ctl.signal)) {
          if (event.type === "suggest_toggle") suppressRef.current.add(event.data.kind);
          if (event.type === "done" || event.type === "error") finished = true;
          dispatch({ type: "event", id: assistantId, event });
        }
        if (!finished && !ctl.signal.aborted) {
          dispatch({ type: "fail", id: assistantId, message: "" });
        }
      } catch (error) {
        if (!ctl.signal.aborted) {
          dispatch({
            type: "fail",
            id: assistantId,
            message: error instanceof Error ? error.message : "",
          });
        }
      } finally {
        if (abortRef.current === ctl) abortRef.current = null;
      }
    },
    [stream],
  );

  const send = useCallback(
    (text: string, attachments: Attachment[] = []) => {
      const content = text.trim();
      if ((!content && attachments.length === 0) || abortRef.current) return;
      if (!idRef.current) {
        idRef.current = newId();
        setConversationId(idRef.current);
      }
      const user = { ...emptyMessage(newId(), "user"), content, attachments };
      const assistant = pendingAssistant(newId());
      dispatch({ type: "send", user, assistant });
      void run([...messagesRef.current, user], assistant.id);
    },
    [run],
  );

  const regenerate = useCallback(() => {
    if (abortRef.current) return;
    const messages = messagesRef.current;
    const last = messages.at(-1);
    if (last?.role !== "assistant") return;
    const history = messages.slice(0, -1);
    const assistant = pendingAssistant(newId());
    dispatch({ type: "truncate", keep: history.length });
    dispatch({ type: "append", message: assistant });
    void run(history, assistant.id);
  }, [run]);

  const stop = useCallback(() => {
    const ctl = abortRef.current;
    const pending = messagesRef.current.find((m) => m.streaming);
    ctl?.abort();
    abortRef.current = null;
    if (pending) dispatch({ type: "stop", id: pending.id });
  }, []);

  const dismissToggle = useCallback((id: string) => dispatch({ type: "dismiss-toggle", id }), []);

  const acceptToggle = useCallback(
    (id: string, kind: SuggestKind) => {
      if (kind === "kb") setOptions((o) => ({ ...o, knowledge: true }));
      dismissToggle(id);
    },
    [dismissToggle],
  );

  useEffect(() => {
    const id = idRef.current;
    if (wasStreaming.current && !streaming && id && state.messages.length > 0) {
      const first = !persistedRef.current;
      save(id, state.messages.map(toStored))
        .then(() => {
          persistedRef.current = true;
          onSaved?.(id, first);
        })
        .catch(() => onSaveError?.());
    }
    wasStreaming.current = streaming;
  }, [streaming, state.messages, save, onSaved, onSaveError]);

  useEffect(() => () => abortRef.current?.abort(), []);

  return {
    messages: state.messages,
    streaming,
    conversationId,
    options,
    setOptions,
    send,
    stop,
    regenerate,
    dismissToggle,
    acceptToggle,
  };
}

export type ChatController = ReturnType<typeof useChatStream>;
