import "server-only";
import type { z } from "zod";
import { errorBodySchema, upstreamSessionSchema } from "@/lib/api/schemas";
import { csrfGuard } from "./csrf";
import { jsonError, unreachable } from "./http";
import type { UpstreamDeps } from "./refresh";
import type { SessionStore } from "./session-store";

const BAD_REQUEST = "Check the details you entered and try again.";

export async function forwardError(res: Response): Promise<Response> {
  const parsed = errorBodySchema.safeParse(await res.json().catch(() => null));
  const headers = new Headers({ "cache-control": "no-store" });
  const retryAfter = res.headers.get("retry-after");
  if (retryAfter) headers.set("retry-after", retryAfter);
  const { code, message } = parsed.success
    ? parsed.data.error
    : { code: "http_error", message: "Something went wrong. Please try again." };
  return Response.json({ error: { code, message } }, { status: res.status, headers });
}

export async function exchangeCredentials(
  req: Request,
  schema: z.ZodType<object>,
  path: "/auth/login" | "/auth/register",
  store: SessionStore,
  deps: UpstreamDeps,
  appOrigin?: string,
): Promise<Response> {
  const blocked = csrfGuard(req, appOrigin);
  if (blocked) return blocked;

  const input = schema.safeParse(await req.json().catch(() => null));
  if (!input.success) return jsonError(400, "bad_request", BAD_REQUEST);

  let res: Response;
  try {
    res = await deps.fetch(`${deps.apiUrl}${path}`, {
      method: "POST",
      headers: { "content-type": "application/json", "user-agent": deps.device },
      body: JSON.stringify({ ...input.data, device: deps.device }),
      cache: "no-store",
    });
  } catch {
    return unreachable();
  }
  if (!res.ok) return forwardError(res);

  const session = upstreamSessionSchema.safeParse(await res.json().catch(() => null));
  if (!session.success)
    return jsonError(502, "bad_response", "Unexpected response from the server.");
  const { user, ...tokens } = session.data;
  store.write(tokens);
  return Response.json({ user }, { status: res.status, headers: { "cache-control": "no-store" } });
}
