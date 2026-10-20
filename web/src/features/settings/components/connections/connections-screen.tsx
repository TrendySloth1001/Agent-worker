"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { Avatar } from "@/components/ui/avatar";
import { BetaTag } from "@/components/ui/beta-tag";
import { Button } from "@/components/ui/button";
import { ConfirmSheet } from "@/components/ui/confirm-sheet";
import { SettingsGroup, SettingsGroupHeader } from "@/components/ui/settings-group";
import { SettingsTile } from "@/components/ui/settings-tile";
import { Tag } from "@/components/ui/tag";
import { toast } from "@/components/ui/toaster";
import {
  disconnectConnector,
  disconnectGithub,
  fetchConnections,
  startConnector,
} from "../../api/connections";
import { errorMessage } from "../../api/http";
import { settingsKeys } from "../../api/query-keys";
import { CONNECTIONS_COPY } from "../../content/copy";
import { PROVIDER_DRIVE, PROVIDER_GITHUB, type Connection } from "../../schemas/connections";
import { FieldError } from "../form-sheet";
import { ErrorNotice, LoadingRows } from "../query-notice";
import { SettingsPage } from "../settings-page";
import { GithubFlowSheet } from "./github-flow-sheet";
import { useGithubFlow } from "./use-github-flow";

type Disconnecting = typeof PROVIDER_GITHUB | typeof PROVIDER_DRIVE | null;

export function ConnectionsScreen({ backHref }: { backHref?: string | null }) {
  const queryClient = useQueryClient();
  const connections = useQuery({ queryKey: settingsKeys.connections, queryFn: fetchConnections });
  const github = useGithubFlow();
  const [disconnecting, setDisconnecting] = useState<Disconnecting>(null);
  const [driveOpened, setDriveOpened] = useState(false);
  const refresh = () => queryClient.invalidateQueries({ queryKey: settingsKeys.connections });

  const connectDrive = useMutation({
    mutationFn: () => startConnector(PROVIDER_DRIVE),
    onSuccess: (data) => {
      window.open(data.authorizeUrl, "_blank", "noopener,noreferrer");
      setDriveOpened(true);
      toast.message(CONNECTIONS_COPY.drive.opened);
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const disconnect = useMutation({
    mutationFn: (provider: NonNullable<Disconnecting>) =>
      provider === PROVIDER_GITHUB ? disconnectGithub() : disconnectConnector(provider),
    onSuccess: async (_, provider) => {
      toast.success(
        provider === PROVIDER_GITHUB
          ? CONNECTIONS_COPY.github.disconnected
          : CONNECTIONS_COPY.drive.disconnected,
      );
      await refresh();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const find = (provider: string): Connection | undefined =>
    connections.data?.items.find((c) => c.provider === provider);
  const githubConn = find(PROVIDER_GITHUB);
  const driveConn = find(PROVIDER_DRIVE);
  const available = (provider: string): boolean =>
    connections.data?.providers[provider]?.configured ?? false;

  return (
    <SettingsPage title={CONNECTIONS_COPY.title} backHref={backHref}>
      {connections.isPending && <LoadingRows rows={2} />}
      {connections.isError && (
        <ErrorNotice
          message={errorMessage(connections.error)}
          onRetry={() => void connections.refetch()}
        />
      )}
      {connections.data && (
        <section>
          <SettingsGroupHeader>{CONNECTIONS_COPY.group}</SettingsGroupHeader>
          <SettingsGroup>
            <SettingsTile
              leading={
                githubConn?.avatarUrl ? (
                  <Avatar name={githubConn.accountLogin} src={githubConn.avatarUrl} size={40} />
                ) : undefined
              }
              icon="github"
              title={CONNECTIONS_COPY.github.title}
              subtitle={
                githubConn
                  ? CONNECTIONS_COPY.connectedAs(githubConn.accountLogin)
                  : CONNECTIONS_COPY.github.pitch
              }
              badge={
                githubConn?.needsReauth ? (
                  <Tag accent>{CONNECTIONS_COPY.github.reauth}</Tag>
                ) : undefined
              }
              trailing={
                githubConn ? (
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => setDisconnecting(PROVIDER_GITHUB)}
                  >
                    {CONNECTIONS_COPY.github.disconnect}
                  </Button>
                ) : (
                  <Button
                    size="sm"
                    disabled={github.starting || !available(PROVIDER_GITHUB)}
                    onClick={() => void github.start()}
                  >
                    {github.starting
                      ? CONNECTIONS_COPY.github.starting
                      : CONNECTIONS_COPY.github.connect}
                  </Button>
                )
              }
            />
            <SettingsTile
              icon="googleDrive"
              title={CONNECTIONS_COPY.drive.title}
              subtitle={
                driveConn
                  ? CONNECTIONS_COPY.connectedAs(driveConn.accountEmail ?? driveConn.accountLogin)
                  : CONNECTIONS_COPY.drive.summary
              }
              badge={<BetaTag />}
              trailing={
                driveConn ? (
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => setDisconnecting(PROVIDER_DRIVE)}
                  >
                    {CONNECTIONS_COPY.drive.disconnect}
                  </Button>
                ) : driveOpened ? (
                  <Button size="sm" variant="secondary" onClick={() => void refresh()}>
                    {CONNECTIONS_COPY.drive.refresh}
                  </Button>
                ) : (
                  <Button
                    size="sm"
                    disabled={connectDrive.isPending || !available(PROVIDER_DRIVE)}
                    onClick={() => connectDrive.mutate()}
                  >
                    {CONNECTIONS_COPY.drive.connect}
                  </Button>
                )
              }
            />
          </SettingsGroup>
          {github.problem && <FieldError>{github.problem}</FieldError>}
        </section>
      )}
      <GithubFlowSheet flow={github.flow} onCancel={github.cancel} />
      <ConfirmSheet
        open={disconnecting !== null}
        onOpenChange={(open) => !open && setDisconnecting(null)}
        illustration="think"
        kicker={CONNECTIONS_COPY.github.disconnectKicker}
        title={
          disconnecting === PROVIDER_DRIVE
            ? CONNECTIONS_COPY.drive.disconnectTitle
            : CONNECTIONS_COPY.github.disconnectTitle
        }
        body={
          disconnecting === PROVIDER_DRIVE
            ? CONNECTIONS_COPY.drive.disconnectBody
            : CONNECTIONS_COPY.github.disconnectBody
        }
        confirmLabel={CONNECTIONS_COPY.github.disconnect}
        destructive
        onConfirm={() => disconnecting && disconnect.mutate(disconnecting)}
      />
    </SettingsPage>
  );
}
