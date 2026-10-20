import { NextResponse } from "next/server";
import { safeNext } from "@/lib/safe-next";
import { env } from "@/server/env";
import { requestOrigin } from "@/server/http";
import { refreshSession } from "@/server/refresh";
import { cookieSessionStore } from "@/server/session-store";
import { upstreamDeps } from "@/server/upstream";

export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  const params = new URL(req.url).searchParams;
  const next = safeNext(params.get("next"));
  const origin = requestOrigin(req, env.appOrigin);
  const store = await cookieSessionStore();

  const toLogin = (notice?: string) => {
    const target = new URL("/login", origin);
    target.searchParams.set("next", next);
    if (notice) target.searchParams.set("notice", notice);
    return NextResponse.redirect(target);
  };

  if (params.has("stale")) {
    store.clear();
    return toLogin("expired");
  }
  const tokens = await refreshSession(store, upstreamDeps(req));
  return tokens ? NextResponse.redirect(new URL(next, origin)) : toLogin();
}
