import "server-only";

export function jsonError(status: number, code: string, message: string): Response {
  return Response.json(
    { error: { code, message } },
    { status, headers: { "cache-control": "no-store" } },
  );
}

export function requestOrigin(req: Request, configured?: string): string {
  if (configured) return configured;
  const url = new URL(req.url);
  const proto =
    req.headers.get("x-forwarded-proto")?.split(",")[0]?.trim() ?? url.protocol.slice(0, -1);
  const host = req.headers.get("x-forwarded-host") ?? req.headers.get("host") ?? url.host;
  return `${proto}://${host}`;
}

export const unreachable = (): Response =>
  jsonError(502, "upstream_unreachable", "Cannot reach the server. Check your connection.");
