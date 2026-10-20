import { apiFetch } from "@/server/api-fetch";
import { forwardError } from "@/server/auth-flow";
import { unreachable } from "@/server/http";
import { cookieSessionStore } from "@/server/session-store";
import { upstreamDeps } from "@/server/upstream";

export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  try {
    const res = await apiFetch(
      "/auth/me",
      { signal: req.signal },
      await cookieSessionStore(),
      upstreamDeps(req),
    );
    if (!res.ok) return forwardError(res);
    return new Response(res.body, {
      status: 200,
      headers: { "content-type": "application/json", "cache-control": "no-store" },
    });
  } catch {
    return unreachable();
  }
}
