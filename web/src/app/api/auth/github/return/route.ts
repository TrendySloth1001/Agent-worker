import { cookies } from "next/headers";
import { WEB_FLOW_COOKIE } from "@/server/cookie-names";
import { cookieSessionStore } from "@/server/session-store";
import { upstreamDeps } from "@/server/upstream";
import { finishWebSignIn } from "@/server/web-sign-in";

export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  const flow = (await cookies()).get(WEB_FLOW_COOKIE)?.value;
  return finishWebSignIn(req, flow, await cookieSessionStore(), upstreamDeps(req));
}
