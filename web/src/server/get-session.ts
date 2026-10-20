import "server-only";
import { cache } from "react";
import { meSchema, type Me } from "@/lib/api/schemas";
import { apiFetch } from "./api-fetch";
import { cookieSessionStore } from "./session-store";
import { upstreamDeps } from "./upstream";

export type SessionResult =
  { status: "signed-in"; me: Me } | { status: "signed-out" } | { status: "error" };

export const getSession = cache(async (): Promise<SessionResult> => {
  const store = await cookieSessionStore({ readOnly: true });
  if (!store.read().accessToken) return { status: "signed-out" };
  try {
    const res = await apiFetch("/auth/me", { refresh: false }, store, upstreamDeps());
    if (res.status === 401) return { status: "signed-out" };
    if (!res.ok) return { status: "error" };
    const me = meSchema.safeParse(await res.json().catch(() => null));
    return me.success ? { status: "signed-in", me: me.data } : { status: "error" };
  } catch {
    return { status: "error" };
  }
});
