"use client";

import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { ConfirmSheet } from "@/components/ui/confirm-sheet";
import { SettingsGroup, SettingsGroupHeader } from "@/components/ui/settings-group";
import { SettingsTile } from "@/components/ui/settings-tile";
import { errorMessage } from "../../api/http";
import { fetchKeys } from "../../api/keys";
import { settingsKeys } from "../../api/query-keys";
import { INTRO_COPY, KEYS_COPY, KEYS_INTRO, USAGE_INTRO } from "../../content/copy";
import { markSeen, useSeenFlag } from "../../lib/seen-flag";
import type { KeyProvider } from "../../schemas/keys";
import { IntroSheet } from "../intro-sheet";
import { ErrorNotice, LoadingRows } from "../query-notice";
import { SettingsPage } from "../settings-page";
import { KeySheet, useRemoveKey } from "./key-sheet";
import { KeyStatusTag } from "./key-status-tag";
import { KeyUsageSection } from "./key-usage";

const KEYS_INTRO_FLAG = "keys-intro";
const USAGE_INTRO_FLAG = "usage-intro";

export function KeysScreen({
  backHref,
  autoIntro = true,
}: {
  backHref?: string | null;
  autoIntro?: boolean;
}) {
  const keys = useQuery({ queryKey: settingsKeys.keys, queryFn: fetchKeys });
  const [editing, setEditing] = useState<KeyProvider | null>(null);
  const [removing, setRemoving] = useState<KeyProvider | null>(null);
  const [keysManual, setKeysManual] = useState(false);
  const [usageManual, setUsageManual] = useState(false);
  const keysSeen = useSeenFlag(KEYS_INTRO_FLAG);
  const usageSeen = useSeenFlag(USAGE_INTRO_FLAG);
  const remove = useRemoveKey(() => setEditing(null));
  const hasValidKey = keys.data?.hasValidKey ?? false;
  const keysIntro = keysManual || (autoIntro && !keysSeen);
  const usageIntro = usageManual || (autoIntro && keysSeen && hasValidKey && !usageSeen);

  return (
    <SettingsPage title={KEYS_COPY.title} backHref={backHref}>
      <p className="px-lg text-body-small text-text-secondary">{KEYS_COPY.lead}</p>
      <div className="px-lg">
        <Button size="sm" variant="secondary" onClick={() => setKeysManual(true)}>
          {KEYS_COPY.howItWorks}
        </Button>
      </div>
      <section>
        <SettingsGroupHeader>{KEYS_COPY.providers}</SettingsGroupHeader>
        {keys.isPending && <LoadingRows rows={4} />}
        {keys.isError && (
          <ErrorNotice message={errorMessage(keys.error)} onRetry={() => void keys.refetch()} />
        )}
        {keys.data && (
          <SettingsGroup>
            {keys.data.providers.map((provider) => (
              <SettingsTile
                key={provider.id}
                icon="key"
                title={provider.name}
                subtitle={provider.key ? KEYS_COPY.endsWith(provider.key.hint) : provider.blurb}
                badge={provider.key ? <KeyStatusTag status={provider.key.status} /> : undefined}
                value={provider.key ? undefined : KEYS_COPY.emptyRow}
                chevron
                onClick={() => setEditing(provider)}
              />
            ))}
          </SettingsGroup>
        )}
      </section>
      <KeyUsageSection onHowItWorks={() => setUsageManual(true)} />
      <KeySheet
        provider={editing}
        onOpenChange={(open) => !open && setEditing(null)}
        onRemove={setRemoving}
      />
      <ConfirmSheet
        open={removing !== null}
        onOpenChange={(open) => !open && setRemoving(null)}
        illustration="think"
        kicker={KEYS_COPY.removeKicker}
        title={KEYS_COPY.removeTitle}
        body={removing ? KEYS_COPY.removeBody(removing.name) : undefined}
        confirmLabel={KEYS_COPY.remove}
        destructive
        onConfirm={() => removing && remove.mutate(removing.id)}
      />
      <IntroSheet
        open={keysIntro}
        onOpenChange={(open) => {
          if (open) return;
          setKeysManual(false);
          markSeen(KEYS_INTRO_FLAG);
        }}
        pages={KEYS_INTRO}
        doneLabel={INTRO_COPY.keysDone}
        onDone={() => keys.data?.providers[0] && setEditing(keys.data.providers[0])}
      />
      <IntroSheet
        open={usageIntro}
        onOpenChange={(open) => {
          if (open) return;
          setUsageManual(false);
          markSeen(USAGE_INTRO_FLAG);
        }}
        pages={USAGE_INTRO}
        doneLabel={INTRO_COPY.usageDone}
      />
    </SettingsPage>
  );
}
