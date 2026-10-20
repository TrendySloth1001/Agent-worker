"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { ConfirmSheet } from "@/components/ui/confirm-sheet";
import { IconButton } from "@/components/ui/icon-button";
import { Input } from "@/components/ui/input";
import { SettingsGroup, SettingsGroupHeader } from "@/components/ui/settings-group";
import { SettingsTile } from "@/components/ui/settings-tile";
import { Tag } from "@/components/ui/tag";
import { toast } from "@/components/ui/toaster";
import { errorMessage } from "../../api/http";
import {
  addSource,
  deleteSource,
  fetchSources,
  fetchStats,
  refreshSource,
} from "../../api/knowledge";
import { settingsKeys } from "../../api/query-keys";
import { KNOWLEDGE_COPY } from "../../content/copy";
import {
  isSourceActive,
  sourceInputSchema,
  type KnowledgeStats,
  type Source,
} from "../../schemas/knowledge";
import { FieldError } from "../form-sheet";
import { EmptyNotice, ErrorNotice, LoadingRows } from "../query-notice";
import { SettingsPage } from "../settings-page";
import { NoteSheet } from "./note-sheet";

const POLL_MS = 3000;

const statusLabel = (status: string): string =>
  status in KNOWLEDGE_COPY.status
    ? KNOWLEDGE_COPY.status[status as keyof typeof KNOWLEDGE_COPY.status]
    : status;

export function KnowledgeScreen({ backHref }: { backHref?: string | null }) {
  const queryClient = useQueryClient();
  const [link, setLink] = useState("");
  const [problem, setProblem] = useState<string | null>(null);
  const [noteOpen, setNoteOpen] = useState(false);
  const [deleting, setDeleting] = useState<Source | null>(null);

  const sources = useQuery({
    queryKey: settingsKeys.sources,
    queryFn: fetchSources,
    refetchInterval: (q) => (q.state.data?.sources.some(isSourceActive) ? POLL_MS : false),
  });
  const stats = useQuery({ queryKey: settingsKeys.stats, queryFn: fetchStats });
  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey: settingsKeys.sources });
    await queryClient.invalidateQueries({ queryKey: settingsKeys.stats });
  };

  const add = useMutation({
    mutationFn: addSource,
    onSuccess: async () => {
      setLink("");
      toast.success(KNOWLEDGE_COPY.added);
      await refresh();
    },
    onError: (error) => setProblem(errorMessage(error)),
  });
  const reread = useMutation({
    mutationFn: refreshSource,
    onSuccess: async () => {
      toast.success(KNOWLEDGE_COPY.refreshing);
      await refresh();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  const remove = useMutation({
    mutationFn: deleteSource,
    onSuccess: async () => {
      toast.success(KNOWLEDGE_COPY.deleted);
      await refresh();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const submitLink = () => {
    const parsed = sourceInputSchema.safeParse(link);
    if (!parsed.success) return setProblem(parsed.error.issues[0]?.message ?? null);
    setProblem(null);
    add.mutate(parsed.data);
  };

  return (
    <SettingsPage title={KNOWLEDGE_COPY.title} backHref={backHref}>
      <p className="px-lg text-body-small text-text-secondary">{KNOWLEDGE_COPY.lead}</p>
      {stats.data && <StatsRow stats={stats.data} />}
      <section className="flex flex-col gap-sm">
        <SettingsGroupHeader>{KNOWLEDGE_COPY.addGroup}</SettingsGroupHeader>
        <form
          className="flex gap-sm"
          onSubmit={(event) => {
            event.preventDefault();
            submitLink();
          }}
        >
          <Input
            type="text"
            inputMode="url"
            value={link}
            placeholder={KNOWLEDGE_COPY.linkHint}
            aria-label={KNOWLEDGE_COPY.linkLabel}
            aria-invalid={problem !== null}
            onChange={(event) => setLink(event.target.value)}
          />
          <Button type="submit" disabled={add.isPending}>
            {KNOWLEDGE_COPY.addLink}
          </Button>
        </form>
        {problem && <FieldError>{problem}</FieldError>}
        <SettingsGroup>
          <SettingsTile
            icon="edit"
            title={KNOWLEDGE_COPY.addNote}
            chevron
            onClick={() => setNoteOpen(true)}
          />
        </SettingsGroup>
      </section>
      <section>
        <SettingsGroupHeader>{KNOWLEDGE_COPY.sourcesGroup}</SettingsGroupHeader>
        {sources.isPending && <LoadingRows />}
        {sources.isError && (
          <ErrorNotice
            message={errorMessage(sources.error)}
            onRetry={() => void sources.refetch()}
          />
        )}
        {sources.data && sources.data.sources.length === 0 && (
          <EmptyNotice title={KNOWLEDGE_COPY.empty} hint={KNOWLEDGE_COPY.emptyHint} />
        )}
        {sources.data && sources.data.sources.length > 0 && (
          <SettingsGroup>
            {sources.data.sources.map((source) => (
              <div key={source.id} className="flex items-center gap-md px-lg py-md">
                <div className="flex min-w-0 flex-1 flex-col">
                  <span className="truncate text-body">{source.title ?? source.uri}</span>
                  <span className="truncate text-body-small text-text-secondary">
                    {source.error ?? KNOWLEDGE_COPY.counts(source.docCount, source.chunkCount)}
                  </span>
                </div>
                <Tag accent={source.status === "ready"}>{statusLabel(source.status)}</Tag>
                <IconButton
                  icon="regenerate"
                  variant="ghost"
                  label={`${KNOWLEDGE_COPY.refresh} ${source.title ?? source.uri}`}
                  disabled={isSourceActive(source) || reread.isPending}
                  onClick={() => reread.mutate(source.id)}
                />
                <IconButton
                  icon="delete"
                  variant="ghost"
                  label={`${KNOWLEDGE_COPY.delete} ${source.title ?? source.uri}`}
                  onClick={() => setDeleting(source)}
                />
              </div>
            ))}
          </SettingsGroup>
        )}
      </section>
      <NoteSheet open={noteOpen} onOpenChange={setNoteOpen} />
      <ConfirmSheet
        open={deleting !== null}
        onOpenChange={(open) => !open && setDeleting(null)}
        illustration="emptyHistory"
        kicker={KNOWLEDGE_COPY.deleteKicker}
        title={KNOWLEDGE_COPY.deleteTitle}
        body={KNOWLEDGE_COPY.deleteBody}
        confirmLabel={KNOWLEDGE_COPY.delete}
        destructive
        onConfirm={() => deleting && remove.mutate(deleting.id)}
      />
    </SettingsPage>
  );
}

function StatsRow({ stats }: { stats: KnowledgeStats }) {
  const cells = [
    { label: KNOWLEDGE_COPY.stats.sources, value: stats.sources },
    { label: KNOWLEDGE_COPY.stats.documents, value: stats.documents },
    { label: KNOWLEDGE_COPY.stats.chunks, value: stats.chunks },
  ];
  return (
    <dl className="grid grid-cols-3 gap-group-gap *:bg-cell *:px-lg *:py-md [&>*:first-child]:rounded-l-group-outer [&>*:last-child]:rounded-r-group-outer">
      {cells.map((c) => (
        <div key={c.label} className="flex flex-col gap-xxs rounded-group-inner">
          <dt className="font-mono text-caption tracking-[0.08em] text-text-secondary uppercase">
            {c.label}
          </dt>
          <dd className="text-metric font-bold">{c.value}</dd>
        </div>
      ))}
    </dl>
  );
}
