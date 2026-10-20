"use client";

import { useRouter } from "next/navigation";
import { useCallback } from "react";
import { logout } from "../api/account";

export function useSignOut(): () => Promise<void> {
  const router = useRouter();
  return useCallback(async () => {
    await logout().catch(() => undefined);
    router.replace("/login");
    router.refresh();
  }, [router]);
}
