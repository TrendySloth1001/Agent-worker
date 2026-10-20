"use client";

import { useMutation } from "@tanstack/react-query";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "@/components/ui/toaster";
import { changePassword } from "../../api/account";
import { errorMessage } from "../../api/http";
import { PROFILE_COPY } from "../../content/copy";
import { passwordChangeSchema } from "../../schemas/account";
import { FieldError, FieldLabel, FormSheet } from "../form-sheet";

interface PasswordSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  hasPassword: boolean;
}

export function PasswordSheet({ open, onOpenChange, hasPassword }: PasswordSheetProps) {
  return (
    <FormSheet
      open={open}
      onOpenChange={onOpenChange}
      title={hasPassword ? PROFILE_COPY.changePassword : PROFILE_COPY.setPassword}
    >
      {open && <PasswordForm hasPassword={hasPassword} onDone={() => onOpenChange(false)} />}
    </FormSheet>
  );
}

function PasswordForm({ hasPassword, onDone }: { hasPassword: boolean; onDone: () => void }) {
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");
  const [problem, setProblem] = useState<string | null>(null);

  const save = useMutation({
    mutationFn: changePassword,
    onSuccess: () => {
      toast.success(PROFILE_COPY.passwordSaved);
      onDone();
    },
    onError: (error) => setProblem(errorMessage(error)),
  });

  const submit = () => {
    const parsed = passwordChangeSchema.safeParse({
      current: hasPassword ? current : undefined,
      next,
    });
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
      {hasPassword && (
        <div className="flex flex-col gap-xs">
          <FieldLabel htmlFor="password-current">{PROFILE_COPY.currentPassword}</FieldLabel>
          <Input
            id="password-current"
            type="password"
            autoComplete="current-password"
            value={current}
            onChange={(event) => setCurrent(event.target.value)}
          />
        </div>
      )}
      <div className="flex flex-col gap-xs">
        <FieldLabel htmlFor="password-next">{PROFILE_COPY.newPassword}</FieldLabel>
        <Input
          id="password-next"
          type="password"
          autoComplete="new-password"
          value={next}
          onChange={(event) => setNext(event.target.value)}
        />
      </div>
      {problem && <FieldError>{problem}</FieldError>}
      <Button type="submit" fullWidth disabled={save.isPending}>
        {hasPassword ? PROFILE_COPY.changePassword : PROFILE_COPY.setPassword}
      </Button>
    </form>
  );
}
