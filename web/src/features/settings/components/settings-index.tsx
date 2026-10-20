"use client";

import { useQuery } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Avatar } from "@/components/ui/avatar";
import { ConfirmSheet } from "@/components/ui/confirm-sheet";
import type { IconName } from "@/components/ui/icons";
import { SettingsGroup } from "@/components/ui/settings-group";
import { SettingsTile } from "@/components/ui/settings-tile";
import { toast } from "@/components/ui/toaster";
import { fetchMe } from "../api/account";
import { settingsKeys } from "../api/query-keys";
import { CATEGORY_COPY, SETTINGS_COPY } from "../content/copy";
import { displayName } from "../lib/format";
import { usePreferences } from "../preferences/use-preferences";
import { SettingsPage } from "./settings-page";
import { useSignOut } from "./use-sign-out";

type CategoryId = keyof typeof CATEGORY_COPY;

interface Category {
  id: CategoryId;
  icon: IconName;
  path: string;
}

const GROUPS: ReadonlyArray<ReadonlyArray<Category>> = [
  [
    { id: "profile", icon: "personalization", path: "/settings/profile" },
    { id: "models", icon: "models", path: "/settings/models" },
  ],
  [
    { id: "memory", icon: "memory", path: "/settings/memory" },
    { id: "knowledge", icon: "library", path: "/settings/knowledge" },
  ],
  [
    { id: "connections", icon: "apps", path: "/settings/connections" },
    { id: "keys", icon: "key", path: "/settings/api-keys" },
  ],
  [
    { id: "appearance", icon: "appearance", path: "/settings/appearance" },
    { id: "about", icon: "about", path: "/settings/about" },
  ],
];

interface SettingsIndexProps {
  onNavigate?: (path: string) => void;
}

export function SettingsIndex({ onNavigate }: SettingsIndexProps) {
  const router = useRouter();
  const signOut = useSignOut();
  const { reset } = usePreferences();
  const me = useQuery({ queryKey: settingsKeys.me, queryFn: fetchMe });
  const [logoutOpen, setLogoutOpen] = useState(false);
  const [resetOpen, setResetOpen] = useState(false);
  const go = (path: string) => (onNavigate ? onNavigate(path) : router.push(path));
  const user = me.data?.user;

  return (
    <SettingsPage title={SETTINGS_COPY.title} backHref={null}>
      <SettingsGroup>
        <SettingsTile
          leading={
            <Avatar
              name={user ? displayName(user) : undefined}
              src={user?.avatarUrl ?? undefined}
              size={56}
            />
          }
          title={user ? displayName(user) : SETTINGS_COPY.accountFallback}
          subtitle={user?.email ?? SETTINGS_COPY.accountHelp}
          chevron
          onClick={() => go("/settings/profile")}
        />
      </SettingsGroup>
      {GROUPS.map((group) => (
        <SettingsGroup key={group[0]?.id}>
          {group.map((category) => (
            <SettingsTile
              key={category.id}
              icon={category.icon}
              title={CATEGORY_COPY[category.id].title}
              subtitle={CATEGORY_COPY[category.id].summary}
              chevron
              onClick={() => go(category.path)}
            />
          ))}
        </SettingsGroup>
      ))}
      <SettingsGroup>
        <SettingsTile
          icon="reset"
          title={SETTINGS_COPY.reset.title}
          subtitle={SETTINGS_COPY.reset.help}
          onClick={() => setResetOpen(true)}
        />
        <SettingsTile
          icon="logout"
          title={SETTINGS_COPY.logout.title}
          subtitle={SETTINGS_COPY.logout.help}
          danger
          onClick={() => setLogoutOpen(true)}
        />
      </SettingsGroup>
      <ConfirmSheet
        open={resetOpen}
        onOpenChange={setResetOpen}
        illustration="think"
        kicker="RESET"
        title={SETTINGS_COPY.reset.confirmTitle}
        body={SETTINGS_COPY.reset.confirmBody}
        confirmLabel={SETTINGS_COPY.reset.title}
        destructive
        onConfirm={() => {
          reset();
          toast.success(SETTINGS_COPY.reset.done);
        }}
      />
      <ConfirmSheet
        open={logoutOpen}
        onOpenChange={setLogoutOpen}
        illustration="hello"
        kicker={SETTINGS_COPY.logout.kicker}
        title={SETTINGS_COPY.logout.confirmTitle}
        body={SETTINGS_COPY.logout.body}
        confirmLabel={SETTINGS_COPY.logout.title}
        cancelLabel={SETTINGS_COPY.logout.stay}
        onConfirm={() => void signOut()}
      />
    </SettingsPage>
  );
}
