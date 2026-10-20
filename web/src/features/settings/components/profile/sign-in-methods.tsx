"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { SettingsGroup, SettingsGroupHeader } from "@/components/ui/settings-group";
import { SettingsTile } from "@/components/ui/settings-tile";
import { toast } from "@/components/ui/toaster";
import { fetchSignInMethods, unlinkIdentity } from "../../api/account";
import { errorMessage } from "../../api/http";
import { settingsKeys } from "../../api/query-keys";
import { PROFILE_COPY } from "../../content/copy";
import { ErrorNotice, LoadingRows } from "../query-notice";
import { PasswordSheet } from "./password-sheet";

const providerLabel = (provider: string): string =>
  provider === "github" ? "GitHub" : provider === "google" ? "Google" : provider;

export function SignInMethods() {
  const queryClient = useQueryClient();
  const [passwordOpen, setPasswordOpen] = useState(false);
  const methods = useQuery({ queryKey: settingsKeys.signIn, queryFn: fetchSignInMethods });

  const unlink = useMutation({
    mutationFn: unlinkIdentity,
    onSuccess: () => {
      toast.success(PROFILE_COPY.unlinked);
      return queryClient.invalidateQueries({ queryKey: settingsKeys.signIn });
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <section>
      <SettingsGroupHeader>{PROFILE_COPY.methodsGroup}</SettingsGroupHeader>
      {methods.isPending && <LoadingRows rows={2} />}
      {methods.isError && (
        <ErrorNotice message={errorMessage(methods.error)} onRetry={() => void methods.refetch()} />
      )}
      {methods.data && (
        <SettingsGroup>
          <SettingsTile
            icon="lock"
            title={PROFILE_COPY.password}
            subtitle={
              methods.data.hasPassword ? PROFILE_COPY.changePassword : PROFILE_COPY.setPassword
            }
            value={methods.data.hasPassword ? PROFILE_COPY.passwordSet : PROFILE_COPY.passwordNone}
            chevron
            onClick={() => setPasswordOpen(true)}
          />
          {methods.data.identities.map((identity) => (
            <SettingsTile
              key={identity.id}
              icon={identity.provider === "github" ? "github" : "profileName"}
              title={providerLabel(identity.provider)}
              subtitle={identity.login ?? identity.email ?? undefined}
              trailing={
                <Button
                  size="sm"
                  variant="secondary"
                  disabled={unlink.isPending}
                  onClick={() => unlink.mutate(identity.id)}
                  aria-label={`${PROFILE_COPY.unlink} ${providerLabel(identity.provider)}`}
                >
                  {PROFILE_COPY.unlink}
                </Button>
              }
            />
          ))}
        </SettingsGroup>
      )}
      <PasswordSheet
        open={passwordOpen}
        onOpenChange={setPasswordOpen}
        hasPassword={methods.data?.hasPassword ?? true}
      />
    </section>
  );
}
