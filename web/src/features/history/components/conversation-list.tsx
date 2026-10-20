"use client";

import { useState } from "react";
import { ConfirmSheet } from "@/components/ui/confirm-sheet";
import { Skeleton } from "@/components/ui/skeleton";
import type { ConversationSummary } from "@/features/chat/schemas/conversation";
import { groupConversations, HISTORY_COPY as COPY } from "../grouping";
import { ConversationRow, type RowActions } from "./conversation-row";

interface ConversationListProps extends Omit<RowActions, "onDelete"> {
  conversations: readonly ConversationSummary[] | undefined;
  activeId?: string;
  query: string;
  error: boolean;
  now?: Date;
  onDelete: (id: string) => void;
  onNavigate?: () => void;
}

export function ConversationList({
  conversations,
  activeId,
  query,
  error,
  now,
  onNavigate,
  onRename,
  onPin,
  onDelete,
}: ConversationListProps) {
  const [pendingDelete, setPendingDelete] = useState<string | null>(null);

  if (!conversations && !error) {
    return (
      <div className="flex flex-col gap-sm px-sm" aria-label="Loading chats">
        {[0, 1, 2, 3, 4].map((i) => (
          <Skeleton key={i} className="h-9" />
        ))}
      </div>
    );
  }
  if (error && !conversations) {
    return <p className="px-lg text-body-small text-text-secondary">{COPY.loadFailed}</p>;
  }
  if (!conversations || conversations.length === 0) {
    return (
      <p className="px-lg text-body-small text-text-secondary">
        {query ? `${COPY.noMatches} “${query}”.` : COPY.noChats}
      </p>
    );
  }

  const groups = groupConversations(conversations, now ?? new Date());
  return (
    <>
      <nav className="flex flex-col gap-lg px-sm" aria-label="Chats">
        {groups.map((g) => (
          <section key={g.label} className="flex flex-col gap-xxs">
            <h2 className="px-md pb-xs font-mono text-caption tracking-[0.1em] text-text-tertiary">{g.label}</h2>
            {g.items.map((c) => (
              <ConversationRow
                key={c.id}
                conversation={c}
                active={c.id === activeId}
                onNavigate={onNavigate}
                onRename={onRename}
                onPin={onPin}
                onDelete={setPendingDelete}
              />
            ))}
          </section>
        ))}
      </nav>
      <ConfirmSheet
        open={pendingDelete !== null}
        onOpenChange={(open) => !open && setPendingDelete(null)}
        onConfirm={() => pendingDelete && onDelete(pendingDelete)}
        illustration="emptyHistory"
        kicker={COPY.deleteKicker}
        title={COPY.deleteTitle}
        body={COPY.deleteBody}
        confirmLabel={COPY.delete}
        destructive
      />
    </>
  );
}
