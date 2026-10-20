"use client";

import { useQuery } from "@tanstack/react-query";
import { fetchMe } from "../../api/account";
import { errorMessage } from "../../api/http";
import { settingsKeys } from "../../api/query-keys";
import { PROFILE_COPY } from "../../content/copy";
import { ErrorNotice, LoadingRows } from "../query-notice";
import { SettingsPage } from "../settings-page";
import { DeleteAccount } from "./delete-account";
import { ProfileHero } from "./profile-hero";
import { SessionsList } from "./sessions-list";
import { SignInMethods } from "./sign-in-methods";

export function ProfileScreen({ backHref }: { backHref?: string | null }) {
  const me = useQuery({ queryKey: settingsKeys.me, queryFn: fetchMe });

  return (
    <SettingsPage title={PROFILE_COPY.title} backHref={backHref}>
      {me.isPending && <LoadingRows />}
      {me.isError && (
        <ErrorNotice message={errorMessage(me.error)} onRetry={() => void me.refetch()} />
      )}
      {me.data && (
        <>
          <ProfileHero key={me.data.user.id} user={me.data.user} />
          <SignInMethods />
          <SessionsList />
          <DeleteAccount
            hasPassword={me.data.user.hasPassword}
            isOwner={me.data.user.role === "owner"}
          />
        </>
      )}
    </SettingsPage>
  );
}
