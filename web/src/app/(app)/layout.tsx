import { headers } from "next/headers";
import { redirect } from "next/navigation";
import type { ReactNode } from "react";
import { safeNext } from "@/lib/safe-next";
import { SESSION_PATH } from "@/lib/route-guard";
import { getSession } from "@/server/get-session";
import { PATH_HEADER } from "@/server/headers";

export default async function AppLayout({ children }: { children: ReactNode }) {
  const session = await getSession();
  if (session.status === "error") throw new Error("Could not load your account.");
  if (session.status === "signed-out") {
    const next = safeNext((await headers()).get(PATH_HEADER));
    redirect(`${SESSION_PATH}?stale=1&next=${encodeURIComponent(next)}`);
  }
  return children;
}
