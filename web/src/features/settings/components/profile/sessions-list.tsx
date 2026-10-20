"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { SettingsGroup, SettingsGroupHeader } from "@/components/ui/settings-group";
import { SettingsTile } from "@/components/ui/settings-tile";
import { Tag } from "@/components/ui/tag";
import { toast } from "@/components/ui/toaster";
import { fetchSessions, revokeSession } from "../../api/account";
import { errorMessage } from "../../api/http";
import { settingsKeys } from "../../api/query-keys";
import { PROFILE_COPY } from "../../content/copy";
import { formatDate } from "../../lib/format";
import { ErrorNotice, LoadingRows } from "../query-notice";

export function SessionsList() {
  const queryClient = useQueryClient();
  const sessions = useQuery({ queryKey: settingsKeys.sessions, queryFn: fetchSessions });
  const refresh = () => queryClient.invalidateQueries({ queryKey: settingsKeys.sessions });

  const revoke = useMutation({
    mutationFn: revokeSession,
    onSuccess: refresh,
    onError: (error) => toast.error(errorMessage(error)),
  });

  const revokeOthers = useMutation({
    mutationFn: async (ids: string[]) => {
      await Promise.all(ids.map(revokeSession));
    },
    onSuccess: async () => {
      toast.success(PROFILE_COPY.othersSignedOut);
      await refresh();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const others = sessions.data?.sessions.filter((s) => !s.current) ?? [];

  return (
    <section>
      <SettingsGroupHeader>{PROFILE_COPY.devicesGroup}</SettingsGroupHeader>
      {sessions.isPending && <LoadingRows rows={2} />}
      {sessions.isError && (
        <ErrorNotice
          message={errorMessage(sessions.error)}
          onRetry={() => void sessions.refetch()}
        />
      )}
      {sessions.data && (
        <SettingsGroup>
          {sessions.data.sessions.map((session) => (
            <SettingsTile
              key={session.id}
              icon="themeSystem"
              title={session.device ?? "Unknown device"}
              subtitle={`Signed in ${formatDate(session.createdAt)}`}
              badge={session.current ? <Tag accent>{PROFILE_COPY.thisDevice}</Tag> : undefined}
              trailing={
                session.current ? undefined : (
                  <Button
                    size="sm"
                    variant="secondary"
                    disabled={revoke.isPending}
                    onClick={() => revoke.mutate(session.id)}
                    aria-label={`${PROFILE_COPY.signOutDevice} ${session.device ?? "device"}`}
                  >
                    {PROFILE_COPY.signOutDevice}
                  </Button>
                )
              }
            />
          ))}
          {others.length > 0 ? (
            <SettingsTile
              icon="logout"
              title={PROFILE_COPY.signOutOthers}
              subtitle={PROFILE_COPY.signOutOthersHelp}
              onClick={() => revokeOthers.mutate(others.map((s) => s.id))}
            />
          ) : (
            <SettingsTile title={PROFILE_COPY.noDevices} />
          )}
        </SettingsGroup>
      )}
    </section>
  );
}
