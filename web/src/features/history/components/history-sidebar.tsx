"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Icon } from "@/components/ui/icon";
import { Input } from "@/components/ui/input";
import { Kbd } from "@/components/ui/kbd";
import { HISTORY_COPY as COPY } from "../grouping";
import { useConversationActions, useConversations } from "../api/use-conversations";
import { ConversationList } from "./conversation-list";

const SEARCH_DEBOUNCE_MS = 250;

export function useDebounced<T>(value: T, ms: number): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const t = setTimeout(() => setDebounced(value), ms);
    return () => clearTimeout(t);
  }, [value, ms]);
  return debounced;
}

export function HistorySidebar({ onNavigate }: { onNavigate?: () => void }) {
  const router = useRouter();
  const activeId = /^\/chat\/([^/]+)/.exec(usePathname())?.[1];
  const [search, setSearch] = useState("");
  const query = useDebounced(search.trim(), SEARCH_DEBOUNCE_MS);
  const { data, isError } = useConversations(query);
  const { rename, pin, remove } = useConversationActions();

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-md">
      <div className="flex flex-col gap-sm px-md">
        <Button
          plain
          fullWidth
          onClick={() => {
            router.push("/chat");
            onNavigate?.();
          }}
        >
          <Icon name="newChat" size="sm" />
          {COPY.newChat}
          <Kbd className="ml-auto border-text-inverse/30 bg-transparent text-text-inverse/70">⌘K</Kbd>
        </Button>
        <div className="relative">
          <Icon name="search" size="sm" className="pointer-events-none absolute top-1/2 left-md -translate-y-1/2 text-text-tertiary" />
          <Input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder={COPY.searchHint}
            aria-label={COPY.searchHint}
            className="h-11 pl-[40px] text-body-small"
          />
        </div>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto pb-lg">
        <ConversationList
          conversations={data}
          activeId={activeId}
          query={query}
          error={isError}
          onNavigate={onNavigate}
          onRename={(id, title) => rename.mutate({ id, title })}
          onPin={(id, pinned) => pin.mutate({ id, pinned })}
          onDelete={(id) =>
            remove.mutate(id, {
              onSuccess: () => {
                if (id === activeId) router.push("/chat");
              },
            })
          }
        />
      </div>
    </div>
  );
}
