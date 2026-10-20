import "server-only";
import { NextResponse } from "next/server";
import { safeNext } from "@/lib/safe-next";
import { upstreamSessionSchema, webStartSchema } from "@/lib/api/schemas";
import { env } from "./env";
import { requestOrigin } from "./http";
import type { UpstreamDeps } from "./refresh";
import { clearedWebFlowCookie, webFlowCookie, type CookieSpec } from "./session-cookies";
import type { SessionStore } from "./session-store";

export type WebSignInError = "unavailable" | "denied" | "failed";

interface FlowCookie {
  state: string;
  next: string;
}

export const encodeFlow = ({ state, next }: FlowCookie): string =>
  `${state}|${encodeURIComponent(next)}`;

export function decodeFlow(value: string | undefined): FlowCookie | null {
  if (!value) return null;
  const at = value.indexOf("|");
  if (at < 1) return null;
  return { state: value.slice(0, at), next: safeNext(decodeURIComponent(value.slice(at + 1))) };
}

function redirectTo(
  req: Request,
  path: string,
  cookies: CookieSpec[],
  params: Record<string, string> = {},
): NextResponse {
  const target = new URL(path, requestOrigin(req, env.appOrigin));
  for (const [key, value] of Object.entries(params)) target.searchParams.set(key, value);
  const res = NextResponse.redirect(target);
  for (const { name, value, options } of cookies) res.cookies.set(name, value, options);
  return res;
}

const failure = (req: Request, error: WebSignInError, next: string) =>
  redirectTo(req, "/login", [clearedWebFlowCookie(env.cookieSecure)], { error, next });

export async function startWebSignIn(req: Request, deps: UpstreamDeps): Promise<Response> {
  const next = safeNext(new URL(req.url).searchParams.get("next"));
  let started: ReturnType<typeof webStartSchema.safeParse>;
  try {
    const res = await deps.fetch(`${deps.apiUrl}/auth/github/web/start`, {
      method: "POST",
      headers: { "content-type": "application/json", "user-agent": deps.device },
      body: JSON.stringify({
        mode: "signin",
        device: deps.device,
        returnOrigin: requestOrigin(req, env.appOrigin),
      }),
      cache: "no-store",
    });
    started = webStartSchema.safeParse(res.ok ? await res.json().catch(() => null) : null);
  } catch {
    return failure(req, "unavailable", next);
  }
  if (!started.success) return failure(req, "unavailable", next);

  const res = NextResponse.redirect(started.data.authorizeUrl);
  const cookie = webFlowCookie(encodeFlow({ state: started.data.state, next }), env.cookieSecure);
  res.cookies.set(cookie.name, cookie.value, cookie.options);
  return res;
}

export async function finishWebSignIn(
  req: Request,
  flowCookie: string | undefined,
  store: SessionStore,
  deps: UpstreamDeps,
): Promise<Response> {
  const params = new URL(req.url).searchParams;
  const flow = decodeFlow(flowCookie);
  const next = flow?.next ?? safeNext(null);
  const ticket = params.get("ticket");

  if (params.get("error")) {
    return failure(req, params.get("error") === "access_denied" ? "denied" : "failed", next);
  }
  if (!flow || !ticket || params.get("state") !== flow.state) return failure(req, "failed", next);

  try {
    const res = await deps.fetch(`${deps.apiUrl}/auth/github/web/redeem`, {
      method: "POST",
      headers: { "content-type": "application/json", "user-agent": deps.device },
      body: JSON.stringify({ ticket }),
      cache: "no-store",
    });
    const session = upstreamSessionSchema.safeParse(
      res.ok ? await res.json().catch(() => null) : null,
    );
    if (!session.success) return failure(req, "failed", next);
    const { accessToken, accessExpiresAt, refreshToken, refreshExpiresAt } = session.data;
    store.write({ accessToken, accessExpiresAt, refreshToken, refreshExpiresAt });
  } catch {
    return failure(req, "unavailable", next);
  }
  return redirectTo(req, next, [clearedWebFlowCookie(env.cookieSecure)]);
}
