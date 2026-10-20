"use client";

import Link from "next/link";
import { DropdownMenu } from "radix-ui";
import { useState } from "react";
import { Icon } from "@/components/ui/icon";
import type { IconName } from "@/components/ui/icons";
import { cn } from "@/lib/cn";
import type { ConversationSummary } from "@/features/chat/schemas/conversation";
import { HISTORY_COPY as COPY } from "../grouping";

export interface RowActions {
  onRename: (id: string, title: string) => void;
  onPin: (id: string, pinned: boolean) => void;
  onDelete: (id: string) => void;
}

interface ConversationRowProps extends RowActions {
  conversation: ConversationSummary;
  active: boolean;
  onNavigate?: () => void;
}

const ITEM =
  "flex cursor-pointer items-center gap-sm rounded-md px-md py-sm text-body-small outline-none data-[highlighted]:bg-surface-raised";

function MenuItem({ icon, label, danger, onSelect }: { icon: IconName; label: string; danger?: boolean; onSelect: () => void }) {
  return (
    <DropdownMenu.Item onSelect={onSelect} className={cn(ITEM, danger && "text-error")}>
      <Icon name={icon} size="sm" />
      {label}
    </DropdownMenu.Item>
  );
}

export function ConversationRow({ conversation: c, active, onNavigate, onRename, onPin, onDelete }: ConversationRowProps) {
  const title = c.title?.trim() || COPY.untitled;
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(title);

  const commit = () => {
    const next = draft.trim();
    setEditing(false);
    if (next && next !== title) onRename(c.id, next);
  };

  if (editing) {
    return (
      <input
        autoFocus
        value={draft}
        maxLength={120}
        aria-label={COPY.chatName}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => {
          if (e.key === "Enter") commit();
          if (e.key === "Escape") setEditing(false);
        }}
        className="h-10 w-full rounded-md border border-accent bg-field px-md text-body-small outline-none"
      />
    );
  }

  return (
    <div
      className={cn(
        "group relative flex items-center rounded-md duration-fast transition-colors ease-standard",
        active ? "bg-surface-raised" : "hover:bg-surface-raised/60",
      )}
    >
      <Link
        href={`/chat/${c.id}`}
        onClick={onNavigate}
        aria-current={active ? "page" : undefined}
        className="flex min-h-10 min-w-0 flex-1 items-center gap-sm rounded-md py-sm pr-xs pl-md outline-none focus-visible:outline-2 focus-visible:outline-accent"
      >
        {active && <span aria-hidden className="size-[6px] shrink-0 rounded-full bg-accent" />}
        {c.pinned && <Icon name="pin" size="xs" className="shrink-0 text-text-tertiary" />}
        <span className={cn("truncate text-body-small", active ? "font-medium text-text-primary" : "text-text-secondary")}>
          {title}
        </span>
      </Link>
      <DropdownMenu.Root>
        <DropdownMenu.Trigger asChild>
          <button
            type="button"
            aria-label={COPY.moreActions}
            className="mr-xs flex size-8 shrink-0 items-center justify-center rounded-full text-text-tertiary opacity-100 outline-none hover:text-text-primary focus-visible:outline-2 focus-visible:outline-accent md:opacity-0 md:group-focus-within:opacity-100 md:group-hover:opacity-100 data-[state=open]:opacity-100"
          >
            <Icon name="more" size="sm" />
          </button>
        </DropdownMenu.Trigger>
        <DropdownMenu.Portal>
          <DropdownMenu.Content
            align="end"
            sideOffset={4}
            className="z-50 min-w-40 animate-pop rounded-menu border border-border bg-surface p-xs shadow-lg"
          >
            <MenuItem
              icon="edit"
              label={COPY.rename}
              onSelect={() => {
                setDraft(title);
                setEditing(true);
              }}
            />
            <MenuItem icon="pin" label={c.pinned ? COPY.unpin : COPY.pin} onSelect={() => onPin(c.id, !c.pinned)} />
            <MenuItem icon="delete" label={COPY.delete} danger onSelect={() => onDelete(c.id)} />
          </DropdownMenu.Content>
        </DropdownMenu.Portal>
      </DropdownMenu.Root>
    </div>
  );
}
