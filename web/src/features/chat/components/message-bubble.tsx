"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Icon } from "@/components/ui/icon";
import type { IconName } from "@/components/ui/icons";
import type { AiModel } from "../api/models";
import { CHAT_COPY, MODEL_INFO_COPY } from "../lib/copy";
import { prettyModelName } from "../lib/pretty-model-name";
import { resolveWait } from "../lib/wait-status";
import { Markdown } from "../markdown/markdown";
import type { UiMessage } from "../state/types";
import { CopyButton } from "./copy-button";
import { ModelInfoSheet } from "./model-info-sheet";
import { AttachmentChip } from "@/features/files";
import { ModelMark } from "./model-mark";
import { SourceChips } from "./source-chips";
import { SuggestionChips } from "./suggestion-chips";
import { WaitStatusLine } from "./wait-status-line";

export function UserBubble({ message }: { message: UiMessage }) {
  return (
    <div className="flex animate-fade flex-col items-end gap-sm">
      {message.attachments.length > 0 && (
        <ul className="flex max-w-[85%] flex-wrap justify-end gap-sm" aria-label="Attachments">
          {message.attachments.map((a) => (
            <li key={a.id}>
              <AttachmentChip attachment={{ name: a.name, size: a.size, kind: a.kind }} />
            </li>
          ))}
        </ul>
      )}
      {message.content && (
        <div className="max-w-[85%] rounded-lg bg-user-bubble px-lg py-md text-body break-words whitespace-pre-wrap text-user-bubble-text">
          {message.content}
        </div>
      )}
    </div>
  );
}

function TextAction({
  icon,
  label,
  onClick,
}: {
  icon: IconName;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="duration-fast inline-flex items-center gap-xs font-mono text-caption tracking-[0.08em] text-text-tertiary uppercase transition-colors ease-standard hover:text-text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
    >
      <Icon name={icon} size="xs" />
      {label}
    </button>
  );
}

interface AssistantMessageProps {
  message: UiMessage;
  models: readonly AiModel[];
  prompt?: string;
  isLast: boolean;
  disabled: boolean;
  onRegenerate: () => void;
  onSuggestion: (text: string) => void;
  onAcceptToggle: (id: string, kind: "kb" | "doc") => void;
  onDismissToggle: (id: string) => void;
}

export function AssistantMessage({
  message: m,
  models,
  prompt,
  isLast,
  disabled,
  onRegenerate,
  onSuggestion,
  onAcceptToggle,
  onDismissToggle,
}: AssistantMessageProps) {
  const [infoOpen, setInfoOpen] = useState(false);
  const waiting = m.streaming && m.content === "";
  const known = models.find((x) => x.id === m.modelId);
  const nameOf = (id: string): string | null => {
    const name = models.find((x) => x.id === id)?.name || prettyModelName(id);
    return name || null;
  };
  const label = m.modelId ? (nameOf(m.modelId) ?? "") : "";
  const canOpenInfo = !m.isError && !waiting && Boolean(m.modelId);
  const finished = !m.streaming;

  return (
    <div className="flex animate-fade flex-col gap-sm">
      {!waiting && (
        <button
          type="button"
          disabled={!canOpenInfo}
          onClick={() => setInfoOpen(true)}
          aria-label={canOpenInfo ? MODEL_INFO_COPY.openHint : undefined}
          className="flex w-fit max-w-full items-center gap-sm disabled:pointer-events-none"
        >
          <ModelMark
            modelId={m.isError ? undefined : m.modelId}
            isError={m.isError && !m.interrupted}
          />
          <span className="truncate font-mono text-caption tracking-[0.08em] text-text-secondary uppercase">
            {m.isError ? "sparky" : label || "sparky"}
          </span>
        </button>
      )}

      {waiting ? (
        <WaitStatusLine step={resolveWait(m, nameOf)} prompt={prompt} />
      ) : m.isError ? (
        m.interrupted ? (
          <div className="flex flex-wrap items-center gap-md">
            <span className="text-body-small text-text-secondary">
              {m.error || CHAT_COPY.interrupted}
            </span>
            <Button plain size="sm" variant="secondary" onClick={onRegenerate} disabled={disabled}>
              {CHAT_COPY.retry}
            </Button>
          </div>
        ) : (
          <p className="text-body text-accent-text">{m.content || m.error}</p>
        )
      ) : (
        <Markdown content={m.content} citations={m.citations} used={m.usedIds} />
      )}

      {m.streaming && m.content !== "" && (
        <span aria-hidden className="size-2 animate-pulse-soft rounded-full bg-accent" />
      )}

      {!m.isError && m.error && <p className="text-caption text-text-secondary">{m.error}</p>}
      {!m.isError && m.notice && <p className="text-caption text-text-secondary">{m.notice}</p>}
      {m.webSearched && !m.streaming && (
        <p className="flex items-center gap-xs text-caption text-text-tertiary">
          <Icon name="web" size="xs" />
          Searched the web
        </p>
      )}

      {m.citations.length > 0 && <SourceChips citations={m.citations} used={m.usedIds} />}

      {finished && isLast && m.toggle?.kind === "kb" && (
        <div className="flex flex-wrap items-center gap-md rounded-md border border-border-strong px-md py-sm">
          <span className="min-w-0 flex-1 text-body-small text-text-secondary">
            {`Your notes might help here (${m.toggle.reason}).`}
          </span>
          <Button plain size="sm" onClick={() => onAcceptToggle(m.id, "kb")}>
            Turn on KB
          </Button>
          <Button plain size="sm" variant="ghost" onClick={() => onDismissToggle(m.id)}>
            Not now
          </Button>
        </div>
      )}

      {finished && isLast && !m.isError && (
        <SuggestionChips items={m.suggestions} onPick={onSuggestion} />
      )}

      {finished && !waiting && !(m.isError && m.interrupted) && (
        <div className="flex flex-wrap items-center gap-lg">
          {!m.isError && <CopyButton text={m.content} />}
          {isLast && (
            <TextAction
              icon="regenerate"
              label={m.isError ? CHAT_COPY.retry : CHAT_COPY.regenerate}
              onClick={onRegenerate}
            />
          )}
        </div>
      )}

      {canOpenInfo && m.modelId && (
        <ModelInfoSheet
          open={infoOpen}
          onOpenChange={setInfoOpen}
          modelId={m.modelId}
          name={label || m.modelId}
          model={known}
          latencyMs={m.latencyMs}
          tokens={m.tokens}
        />
      )}
    </div>
  );
}
