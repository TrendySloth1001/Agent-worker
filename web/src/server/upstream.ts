import "server-only";
import { deviceLabel } from "./device";
import { env } from "./env";
import type { UpstreamDeps } from "./refresh";

export function upstreamDeps(req?: Request): UpstreamDeps {
  return {
    apiUrl: env.apiUrl,
    fetch: (input, init) => fetch(input, init),
    device: deviceLabel(req?.headers.get("user-agent") ?? null),
  };
}
