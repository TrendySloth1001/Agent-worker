import { csrfGuard } from "@/server/csrf";
import { env } from "@/server/env";
import { proxyRequest } from "@/server/proxy-request";
import { cookieSessionStore } from "@/server/session-store";
import { upstreamDeps } from "@/server/upstream";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

interface Context {
  params: Promise<{ path: string[] }>;
}

async function handle(req: Request, { params }: Context): Promise<Response> {
  const blocked = csrfGuard(req, env.appOrigin);
  if (blocked) return blocked;
  const { path } = await params;
  return proxyRequest(
    req,
    path,
    new URL(req.url).search,
    await cookieSessionStore(),
    upstreamDeps(req),
  );
}

export {
  handle as DELETE,
  handle as GET,
  handle as HEAD,
  handle as OPTIONS,
  handle as PATCH,
  handle as POST,
  handle as PUT,
};
