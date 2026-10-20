"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { ConfirmSheet } from "@/components/ui/confirm-sheet";
import { Icon } from "@/components/ui/icon";
import { authApi } from "@/lib/api/client";
import { LOGOUT_COPY } from "./copy";

export function LogoutButton() {
  const router = useRouter();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);

  const logout = useMutation({
    mutationFn: () => authApi.raw("POST", "/logout"),
    onSettled: () => {
      queryClient.clear();
      router.replace("/login");
      router.refresh();
    },
  });

  return (
    <>
      <Button variant="secondary" onClick={() => setOpen(true)} disabled={logout.isPending}>
        <Icon name="logOut" size="sm" />
        {LOGOUT_COPY.action}
      </Button>
      <ConfirmSheet
        open={open}
        onOpenChange={setOpen}
        onConfirm={() => logout.mutate()}
        illustration="hello"
        kicker={LOGOUT_COPY.kicker}
        title={LOGOUT_COPY.title}
        body={LOGOUT_COPY.body}
        confirmLabel={LOGOUT_COPY.action}
        cancelLabel={LOGOUT_COPY.stay}
        destructive
      />
    </>
  );
}
