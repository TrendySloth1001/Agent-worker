"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/components/ui/toaster";
import { errorMessage } from "../../api/http";
import { addNote } from "../../api/knowledge";
import { settingsKeys } from "../../api/query-keys";
import { KNOWLEDGE_COPY } from "../../content/copy";
import { noteDraftSchema } from "../../schemas/knowledge";
import { FieldError, FieldLabel, FormSheet } from "../form-sheet";

interface NoteSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function NoteSheet({ open, onOpenChange }: NoteSheetProps) {
  return (
    <FormSheet open={open} onOpenChange={onOpenChange} title={KNOWLEDGE_COPY.noteTitle}>
      {open && <NoteForm onDone={() => onOpenChange(false)} />}
    </FormSheet>
  );
}

function NoteForm({ onDone }: { onDone: () => void }) {
  const queryClient = useQueryClient();
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [problem, setProblem] = useState<string | null>(null);

  const save = useMutation({
    mutationFn: addNote,
    onSuccess: async () => {
      toast.success(KNOWLEDGE_COPY.added);
      await queryClient.invalidateQueries({ queryKey: settingsKeys.sources });
      await queryClient.invalidateQueries({ queryKey: settingsKeys.stats });
      onDone();
    },
    onError: (error) => setProblem(errorMessage(error)),
  });

  const submit = () => {
    const parsed = noteDraftSchema.safeParse({ title, content });
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
      <FieldLabel htmlFor="note-title">{KNOWLEDGE_COPY.noteTitleLabel}</FieldLabel>
      <Input
        id="note-title"
        value={title}
        maxLength={300}
        onChange={(event) => setTitle(event.target.value)}
      />
      <FieldLabel htmlFor="note-content">{KNOWLEDGE_COPY.noteContentLabel}</FieldLabel>
      <Textarea
        id="note-content"
        rows={5}
        value={content}
        aria-invalid={problem !== null}
        onChange={(event) => setContent(event.target.value)}
      />
      {problem && <FieldError>{problem}</FieldError>}
      <Button type="submit" fullWidth disabled={save.isPending}>
        {KNOWLEDGE_COPY.saveNote}
      </Button>
    </form>
  );
}
