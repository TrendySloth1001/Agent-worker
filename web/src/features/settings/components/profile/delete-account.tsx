"use client";

import { useMutation } from "@tanstack/react-query";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { ConfirmSheet } from "@/components/ui/confirm-sheet";
import { Input } from "@/components/ui/input";
import { SettingsGroup, SettingsGroupHeader } from "@/components/ui/settings-group";
import { SettingsTile } from "@/components/ui/settings-tile";
import { deleteAccount } from "../../api/account";
import { errorMessage } from "../../api/http";
import { PROFILE_COPY } from "../../content/copy";
import { FieldError, FieldLabel, FormSheet } from "../form-sheet";
import { useSignOut } from "../use-sign-out";

export function DeleteAccount({
  hasPassword,
  isOwner,
}: {
  hasPassword: boolean;
  isOwner: boolean;
}) {
  const signOut = useSignOut();
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [passwordOpen, setPasswordOpen] = useState(false);
  const [password, setPassword] = useState("");
  const [problem, setProblem] = useState<string | null>(null);

  const remove = useMutation({
    mutationFn: deleteAccount,
    onSuccess: signOut,
    onError: (error) => setProblem(errorMessage(error)),
  });

  if (isOwner) return null;

  return (
    <section>
      <SettingsGroupHeader>{PROFILE_COPY.dataGroup}</SettingsGroupHeader>
      <SettingsGroup>
        <SettingsTile
          icon="delete"
          title={PROFILE_COPY.deleteAccount}
          subtitle={PROFILE_COPY.deleteHelp}
          danger
          onClick={() => setConfirmOpen(true)}
        />
      </SettingsGroup>
      <ConfirmSheet
        open={confirmOpen}
        onOpenChange={setConfirmOpen}
        illustration="think"
        kicker={PROFILE_COPY.deleteKicker}
        title={PROFILE_COPY.deleteTitle}
        body={PROFILE_COPY.deleteBody}
        confirmLabel={PROFILE_COPY.deleteConfirm}
        destructive
        onConfirm={() => (hasPassword ? setPasswordOpen(true) : remove.mutate(undefined))}
      />
      <FormSheet
        open={passwordOpen}
        onOpenChange={setPasswordOpen}
        title={PROFILE_COPY.deletePasswordTitle}
        description={PROFILE_COPY.deletePasswordBody}
      >
        <form
          className="flex flex-col gap-md"
          onSubmit={(event) => {
            event.preventDefault();
            setProblem(null);
            remove.mutate(password);
          }}
        >
          <FieldLabel htmlFor="delete-password">{PROFILE_COPY.password}</FieldLabel>
          <Input
            id="delete-password"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
          />
          {problem && <FieldError>{problem}</FieldError>}
          <Button
            type="submit"
            variant="danger"
            fullWidth
            disabled={remove.isPending || password.length === 0}
          >
            {PROFILE_COPY.deleteConfirm}
          </Button>
        </form>
      </FormSheet>
    </section>
  );
}
