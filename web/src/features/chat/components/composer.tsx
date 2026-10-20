"use client";

import { useState, type KeyboardEvent, type Ref } from "react";
import { IconButton } from "@/components/ui/icon-button";
import { Textarea } from "@/components/ui/textarea";
import { Tooltip } from "@/components/ui/tooltip";
import { cn } from "@/lib/cn";
import type { WebMode } from "../api/chat-stream";
import { CHAT_COPY } from "../lib/copy";
import type { ComposerOptions } from "../state/use-chat-stream";

const WEB_NEXT: Record<WebMode, WebMode> = { auto: "on", on: "off", off: "auto" };

interface ModeChipProps {
  label: string;
  hint: string;
  state: "off" | "auto" | "on";
  onClick: () => void;
}

function ModeChip({ label, hint, state, onClick }: ModeChipProps) {
  return (
    <Tooltip content={hint}>
      <button
        type="button"
        onClick={onClick}
        aria-pressed={state !== "off"}
        aria-label={hint}
        className={cn(
          "inline-flex h-chip-height items-center rounded-pill border px-md font-mono text-caption tracking-[0.08em] uppercase",
          "duration-fast transition-[background-color,border-color,color] ease-standard",
          "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent",
          state === "on" && "border-text-primary bg-text-primary text-text-inverse",
          state === "auto" && "border-accent text-accent-text",
          state === "off" && "border-border-strong text-text-tertiary hover:text-text-primary",
        )}
      >
        {label}
      </button>
    </Tooltip>
  );
}

interface ComposerProps {
  streaming: boolean;
  options: ComposerOptions;
  onOptionsChange: (next: ComposerOptions) => void;
  onSend: (text: string) => void;
  onStop: () => void;
  onAttach?: () => void;
  inputRef?: Ref<HTMLTextAreaElement>;
}

export function Composer({ streaming, options, onOptionsChange, onSend, onStop, onAttach, inputRef }: ComposerProps) {
  const [text, setText] = useState("");
  const canSend = text.trim() !== "";

  const submit = () => {
    if (!canSend || streaming) return;
    onSend(text);
    setText("");
  };

  const onKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
      e.preventDefault();
      submit();
    }
  };

  return (
    <div className="flex flex-col gap-sm rounded-card border border-border-strong bg-glass p-sm backdrop-blur-md">
      <Textarea
        ref={inputRef}
        value={text}
        onChange={(e) => setText(e.target.value)}
        onKeyDown={onKeyDown}
        placeholder={CHAT_COPY.inputHint}
        aria-label={CHAT_COPY.inputHint}
        enterKeyHint="send"
        className="min-h-12 bg-transparent px-md py-sm focus-visible:border-transparent"
      />
      <div className="flex items-center justify-between gap-sm">
        <div className="flex min-w-0 items-center gap-xs">
          {onAttach && <IconButton icon="attach" label={CHAT_COPY.attach} variant="ghost" onClick={onAttach} />}
          <div className="flex items-center gap-xs overflow-x-auto">
            <ModeChip
              label={CHAT_COPY.web}
              hint={CHAT_COPY.webModes[options.webMode]}
              state={options.webMode === "off" ? "off" : options.webMode === "auto" ? "auto" : "on"}
              onClick={() => onOptionsChange({ ...options, webMode: WEB_NEXT[options.webMode] })}
            />
            <ModeChip
              label={CHAT_COPY.kb}
              hint={options.knowledge ? CHAT_COPY.kbOn : CHAT_COPY.kbOff}
              state={options.knowledge ? "on" : "off"}
              onClick={() => onOptionsChange({ ...options, knowledge: !options.knowledge })}
            />
            <ModeChip
              label={CHAT_COPY.table}
              hint={options.roundTable ? CHAT_COPY.tableOn : CHAT_COPY.tableOff}
              state={options.roundTable ? "on" : "off"}
              onClick={() => onOptionsChange({ ...options, roundTable: !options.roundTable })}
            />
          </div>
        </div>
        {streaming ? (
          <IconButton icon="stop" label={CHAT_COPY.stop} variant="filled" onClick={onStop} />
        ) : (
          <IconButton
            icon="send"
            label={CHAT_COPY.send}
            variant="filled"
            className="disabled:bg-disabled"
            disabled={!canSend}
            onClick={submit}
          />
        )}
      </div>
    </div>
  );
}
