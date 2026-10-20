import { csrfGuard } from "@/server/csrf";
import { env } from "@/server/env";
import { cookieSessionStore } from "@/server/session-store";
import { upstreamDeps } from "@/server/upstream";

export const dynamic = "force-dynamic";

export async function POST(req: Request) {
  const blocked = csrfGuard(req, env.appOrigin);
  if (blocked) return blocked;

  const store = await cookieSessionStore();
  const { refreshToken } = store.read();
  store.clear();
  if (refreshToken) {
    const deps = upstreamDeps(req);
    await deps
      .fetch(`${deps.apiUrl}/auth/logout`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ refreshToken }),
        cache: "no-store",
      })
      .catch(() => undefined);
  }
  return new Response(null, { status: 204, headers: { "cache-control": "no-store" } });
}
