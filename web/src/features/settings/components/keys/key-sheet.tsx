"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Icon } from "@/components/ui/icon";
import { Input } from "@/components/ui/input";
import { toast } from "@/components/ui/toaster";
import { errorMessage } from "../../api/http";
import { removeKey, saveKey, testKey } from "../../api/keys";
import { settingsKeys } from "../../api/query-keys";
import { KEYS_COPY } from "../../content/copy";
import { describeResult } from "../../lib/key-flow";
import { keyInputSchema, type KeyProvider } from "../../schemas/keys";
import { FieldError, FieldLabel, FormSheet } from "../form-sheet";
import { KeyStatusTag } from "./key-status-tag";

interface KeySheetProps {
  provider: KeyProvider | null;
  onOpenChange: (open: boolean) => void;
  onRemove: (provider: KeyProvider) => void;
}

export function KeySheet({ provider, onOpenChange, onRemove }: KeySheetProps) {
  return (
    <FormSheet
      open={provider !== null}
      onOpenChange={onOpenChange}
      title={provider ? KEYS_COPY.sheetTitle(provider.name) : KEYS_COPY.add}
      description={KEYS_COPY.sheetSubtitle}
    >
      {provider && (
        <KeyForm
          key={provider.id}
          provider={provider}
          onRemove={onRemove}
          onDone={() => onOpenChange(false)}
        />
      )}
    </FormSheet>
  );
}

interface KeyFormProps {
  provider: KeyProvider;
  onRemove: (provider: KeyProvider) => void;
  onDone: () => void;
}

function KeyForm({ provider, onRemove, onDone }: KeyFormProps) {
  const queryClient = useQueryClient();
  const [value, setValue] = useState("");
  const [visible, setVisible] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  const refresh = () => queryClient.invalidateQueries({ queryKey: settingsKeys.keys });

  const save = useMutation({
    mutationFn: (key: string) => saveKey(provider.id, key),
    onSuccess: async (data) => {
      await refresh();
      if (data.result === "valid") {
        toast.success(KEYS_COPY.savedWorks);
        return onDone();
      }
      setProblem(describeResult(data.result).message);
    },
    onError: (error) => setProblem(errorMessage(error)),
  });

  const test = useMutation({
    mutationFn: () => testKey(provider.id),
    onSuccess: async (data) => {
      await refresh();
      const outcome = describeResult(data.result);
      if (outcome.tone === "ok") toast.success(outcome.message);
      else toast.error(outcome.message);
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const submit = () => {
    const parsed = keyInputSchema.safeParse(value);
    if (!parsed.success) return setProblem(parsed.error.issues[0]?.message ?? null);
    setProblem(null);
    save.mutate(parsed.data);
  };

  return (
    <div className="flex flex-col gap-lg">
      {provider.key && (
        <div className="flex items-center gap-md rounded-menu bg-cell px-lg py-md">
          <div className="flex min-w-0 flex-1 flex-col">
            <span className="text-body font-medium">{KEYS_COPY.endsWith(provider.key.hint)}</span>
            <span className="text-body-small text-text-secondary">{provider.blurb}</span>
          </div>
          <KeyStatusTag status={provider.key.status} />
        </div>
      )}
      <form
        className="flex flex-col gap-sm"
        onSubmit={(event) => {
          event.preventDefault();
          submit();
        }}
      >
        <FieldLabel htmlFor="api-key">{KEYS_COPY.fieldLabel}</FieldLabel>
        <div className="relative">
          <Input
            id="api-key"
            type={visible ? "text" : "password"}
            value={value}
            autoComplete="off"
            spellCheck={false}
            placeholder={provider.placeholder}
            aria-invalid={problem !== null}
            className="pr-14 font-mono"
            onChange={(event) => setValue(event.target.value)}
          />
          <button
            type="button"
            onClick={() => setVisible(!visible)}
            aria-label={visible ? KEYS_COPY.hide : KEYS_COPY.show}
            className="absolute inset-y-0 right-md my-auto flex size-9 items-center justify-center rounded-full text-text-secondary hover:text-text-primary"
          >
            <Icon name={visible ? "hide" : "show"} />
          </button>
        </div>
        {problem && <FieldError>{problem}</FieldError>}
        <Button type="submit" fullWidth disabled={save.isPending}>
          {save.isPending ? KEYS_COPY.saving : KEYS_COPY.save}
        </Button>
      </form>
      <div className="flex flex-wrap items-center justify-between gap-sm">
        <Button asChild size="sm" variant="ghost">
          <a href={provider.keyUrl} target="_blank" rel="noopener noreferrer">
            {KEYS_COPY.getKey}
            <Icon name="openExternal" size="sm" />
          </a>
        </Button>
        {provider.key && (
          <div className="flex gap-sm">
            <Button
              size="sm"
              variant="secondary"
              disabled={test.isPending}
              onClick={() => test.mutate()}
            >
              {test.isPending ? KEYS_COPY.testing : KEYS_COPY.test}
            </Button>
            <Button size="sm" variant="danger" onClick={() => onRemove(provider)}>
              {KEYS_COPY.remove}
            </Button>
          </div>
        )}
      </div>
    </div>
  );
}

export function useRemoveKey(onDone: () => void) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: removeKey,
    onSuccess: async () => {
      toast.success(KEYS_COPY.removed);
      await queryClient.invalidateQueries({ queryKey: settingsKeys.keys });
      await queryClient.invalidateQueries({ queryKey: ["settings", "key-usage"] });
      onDone();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
}
