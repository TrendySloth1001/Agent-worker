import { loginInputSchema } from "@/lib/api/schemas";
import { exchangeCredentials } from "@/server/auth-flow";
import { env } from "@/server/env";
import { cookieSessionStore } from "@/server/session-store";
import { upstreamDeps } from "@/server/upstream";

export const dynamic = "force-dynamic";

export async function POST(req: Request) {
  return exchangeCredentials(
    req,
    loginInputSchema,
    "/auth/login",
    await cookieSessionStore(),
    upstreamDeps(req),
    env.appOrigin,
  );
}
