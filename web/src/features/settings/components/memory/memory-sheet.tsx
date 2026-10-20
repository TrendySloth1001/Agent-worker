"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/components/ui/toaster";
import { errorMessage } from "../../api/http";
import { createMemory, updateMemory } from "../../api/memory";
import { settingsKeys } from "../../api/query-keys";
import { MEMORY_COPY } from "../../content/copy";
import {
  MEMORY_KINDS,
  MEMORY_TEXT_MAX,
  memoryDraftSchema,
  type Memory,
  type MemoryKind,
} from "../../schemas/memory";
import { FieldError, FieldLabel, FormSheet } from "../form-sheet";
import { OptionChips } from "../option-chips";

export type MemoryEditing = Memory | "new" | null;

interface MemorySheetProps {
  editing: MemoryEditing;
  onOpenChange: (open: boolean) => void;
}

export function MemorySheet({ editing, onOpenChange }: MemorySheetProps) {
  return (
    <FormSheet
      open={editing !== null}
      onOpenChange={onOpenChange}
      title={editing === "new" ? MEMORY_COPY.addTitle : MEMORY_COPY.editTitle}
    >
      {editing && (
        <MemoryForm
          key={editing === "new" ? "new" : editing.id}
          memory={editing === "new" ? null : editing}
          onDone={() => onOpenChange(false)}
        />
      )}
    </FormSheet>
  );
}

function MemoryForm({ memory, onDone }: { memory: Memory | null; onDone: () => void }) {
  const queryClient = useQueryClient();
  const [text, setText] = useState(memory?.text ?? "");
  const [kind, setKind] = useState<MemoryKind>(memory?.kind ?? "fact");
  const [problem, setProblem] = useState<string | null>(null);

  const save = useMutation({
    mutationFn: (draft: { text: string; kind: MemoryKind }) =>
      memory ? updateMemory(memory.id, draft) : createMemory(draft),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: settingsKeys.memoryAll });
      onDone();
    },
    onError: (error) => {
      setProblem(errorMessage(error));
      toast.error(MEMORY_COPY.saveFailed);
    },
  });

  const submit = () => {
    const parsed = memoryDraftSchema.safeParse({ text, kind });
    if (!parsed.success) return setProblem(parsed.error.issues[0]?.message ?? null);
    setProblem(null);
    save.mutate(parsed.data);
  };

  return (
    <form
      className="flex flex-col gap-md"
      onSubmit={(event) => {
        event.preventDefault();
        submit();
      }}
    >
      <FieldLabel htmlFor="memory-text">{MEMORY_COPY.addHint}</FieldLabel>
      <Textarea
        id="memory-text"
        rows={3}
        value={text}
        maxLength={MEMORY_TEXT_MAX}
        aria-invalid={problem !== null}
        onChange={(event) => setText(event.target.value)}
      />
      <OptionChips
        label={MEMORY_COPY.kind}
        value={kind}
        options={MEMORY_KINDS.map((value) => ({ value, label: MEMORY_COPY.kinds[value] }))}
        onChange={setKind}
      />
      {problem && <FieldError>{problem}</FieldError>}
      <Button type="submit" fullWidth disabled={save.isPending}>
        {memory ? MEMORY_COPY.save : MEMORY_COPY.add}
      </Button>
    </form>
  );
}
