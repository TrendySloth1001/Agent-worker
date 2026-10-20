import { startWebSignIn } from "@/server/web-sign-in";
import { upstreamDeps } from "@/server/upstream";

export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  return startWebSignIn(req, upstreamDeps(req));
}
