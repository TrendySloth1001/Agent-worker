"use client";

import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { ConfirmSheet } from "@/components/ui/confirm-sheet";
import { IconButton } from "@/components/ui/icon-button";
import { Input } from "@/components/ui/input";
import { SettingsGroup, SettingsGroupHeader } from "@/components/ui/settings-group";
import { SettingsSwitchTile } from "@/components/ui/settings-switch-tile";
import { Tag } from "@/components/ui/tag";
import { toast } from "@/components/ui/toaster";
import { errorMessage } from "../../api/http";
import {
  clearMemories,
  deleteMemory,
  fetchMemories,
  saveMemorySettings,
  updateMemory,
} from "../../api/memory";
import { settingsKeys } from "../../api/query-keys";
import { MEMORY_COPY } from "../../content/copy";
import { useDebounced } from "../../lib/use-debounced";
import type { Memory, MemoryList } from "../../schemas/memory";
import { EmptyNotice, ErrorNotice, LoadingRows } from "../query-notice";
import { SettingsPage } from "../settings-page";
import { MemorySheet, type MemoryEditing } from "./memory-sheet";

export function MemoryScreen({ backHref }: { backHref?: string | null }) {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");
  const query = useDebounced(search.trim());
  const [editing, setEditing] = useState<MemoryEditing>(null);
  const [clearOpen, setClearOpen] = useState(false);
  const memories = useQuery({
    queryKey: settingsKeys.memory(query),
    queryFn: () => fetchMemories(query),
    placeholderData: keepPreviousData,
  });
  const refresh = () => queryClient.invalidateQueries({ queryKey: settingsKeys.memoryAll });
  const fail = (error: unknown) => toast.error(errorMessage(error));

  const settings = useMutation({
    mutationFn: saveMemorySettings,
    onSuccess: refresh,
    onError: fail,
  });
  const pin = useMutation({
    mutationFn: (m: Memory) => updateMemory(m.id, { pinned: !m.pinned }),
    onSuccess: refresh,
    onError: fail,
  });
  const remove = useMutation({
    mutationFn: deleteMemory,
    onSuccess: async () => {
      toast.success(MEMORY_COPY.deleted);
      await refresh();
    },
    onError: fail,
  });
  const clear = useMutation({
    mutationFn: clearMemories,
    onSuccess: async () => {
      toast.success(MEMORY_COPY.cleared);
      await refresh();
    },
    onError: fail,
  });

  const data = memories.data;

  return (
    <SettingsPage title={MEMORY_COPY.title} backHref={backHref}>
      {memories.isPending && <LoadingRows />}
      {memories.isError && (
        <ErrorNotice
          message={errorMessage(memories.error)}
          onRetry={() => void memories.refetch()}
        />
      )}
      {data && (
        <>
          <SettingsGroup>
            <SettingsSwitchTile
              icon="memory"
              title={MEMORY_COPY.toggle}
              subtitle={MEMORY_COPY.toggleHint}
              checked={data.enabled}
              onCheckedChange={(enabled) => settings.mutate({ enabled })}
            />
            <SettingsSwitchTile
              icon="history"
              title={MEMORY_COPY.recallToggle}
              subtitle={MEMORY_COPY.recallHint}
              checked={data.chatRecall}
              onCheckedChange={(chatRecall) => settings.mutate({ chatRecall })}
            />
          </SettingsGroup>
          <div className="flex gap-sm">
            <Input
              type="search"
              value={search}
              placeholder={MEMORY_COPY.searchHint}
              aria-label={MEMORY_COPY.searchHint}
              onChange={(event) => setSearch(event.target.value)}
            />
            <Button onClick={() => setEditing("new")} aria-label={MEMORY_COPY.addTitle}>
              {MEMORY_COPY.add}
            </Button>
          </div>
          <MemoryItems
            data={data}
            searching={query.length > 0}
            onEdit={setEditing}
            onPin={(m) => pin.mutate(m)}
            onDelete={(m) => remove.mutate(m.id)}
          />
          {data.total > 0 && (
            <SettingsGroup>
              <button
                type="button"
                onClick={() => setClearOpen(true)}
                className="flex min-h-touch-target w-full items-center px-lg text-body text-error hover:bg-cell-high/50"
              >
                {MEMORY_COPY.clearAll}
              </button>
            </SettingsGroup>
          )}
        </>
      )}
      <MemorySheet editing={editing} onOpenChange={(open) => !open && setEditing(null)} />
      <ConfirmSheet
        open={clearOpen}
        onOpenChange={setClearOpen}
        illustration="emptyHistory"
        kicker={MEMORY_COPY.clearKicker}
        title={MEMORY_COPY.clearTitle}
        body={MEMORY_COPY.clearBody}
        confirmLabel={MEMORY_COPY.clearAll}
        destructive
        onConfirm={() => clear.mutate()}
      />
    </SettingsPage>
  );
}

interface MemoryItemsProps {
  data: MemoryList;
  searching: boolean;
  onEdit: (memory: Memory) => void;
  onPin: (memory: Memory) => void;
  onDelete: (memory: Memory) => void;
}

function MemoryItems({ data, searching, onEdit, onPin, onDelete }: MemoryItemsProps) {
  if (data.items.length === 0) {
    if (searching) return <EmptyNotice title={MEMORY_COPY.noMatch} />;
    return data.enabled ? (
      <EmptyNotice title={MEMORY_COPY.empty} hint={MEMORY_COPY.emptyHint} />
    ) : (
      <EmptyNotice title={MEMORY_COPY.emptyOff} hint={MEMORY_COPY.emptyOffHint} />
    );
  }
  return (
    <section>
      <SettingsGroupHeader>{MEMORY_COPY.count(data.total, data.max)}</SettingsGroupHeader>
      <SettingsGroup>
        {data.items.map((memory) => (
          <div key={memory.id} className="flex items-start gap-md px-lg py-md">
            <div className="flex min-w-0 flex-1 flex-col gap-xs">
              <p className="text-body break-words">{memory.text}</p>
              <div className="flex items-center gap-sm">
                <Tag>{MEMORY_COPY.kinds[memory.kind]}</Tag>
                {memory.pinned && <Tag accent>{MEMORY_COPY.pinned}</Tag>}
              </div>
            </div>
            <div className="flex shrink-0">
              <IconButton
                icon="pin"
                variant="ghost"
                label={memory.pinned ? MEMORY_COPY.unpin : MEMORY_COPY.pin}
                onClick={() => onPin(memory)}
              />
              <IconButton
                icon="edit"
                variant="ghost"
                label={MEMORY_COPY.edit}
                onClick={() => onEdit(memory)}
              />
              <IconButton
                icon="delete"
                variant="ghost"
                label={MEMORY_COPY.delete}
                onClick={() => onDelete(memory)}
              />
            </div>
          </div>
        ))}
      </SettingsGroup>
    </section>
  );
}
