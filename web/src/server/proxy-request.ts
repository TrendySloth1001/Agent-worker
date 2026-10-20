import "server-only";
import { apiFetch } from "./api-fetch";
import { jsonError, unreachable } from "./http";
import type { UpstreamDeps } from "./refresh";
import type { SessionStore } from "./session-store";

const HOP_BY_HOP = [
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "proxy-connection",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade",
];

const DROP_REQUEST = [
  ...HOP_BY_HOP,
  "host",
  "cookie",
  "authorization",
  "origin",
  "referer",
  "forwarded",
  "x-forwarded-for",
  "x-forwarded-host",
  "x-forwarded-proto",
  "x-forwarded-port",
  "accept-encoding",
  "expect",
];

const DROP_RESPONSE = [...HOP_BY_HOP, "set-cookie"];
const DECODED_BODY_HEADERS = ["content-encoding", "content-length"];
const BODYLESS_METHODS = new Set(["GET", "HEAD"]);

// Responses on these paths carry session tokens, which must never reach browser code.
const TOKEN_PATHS = [/^auth\/(login|register|refresh|logout|google)$/, /^auth\/github(\/|$)/];

export function upstreamPath(segments: string[], search: string): string | null {
  if (segments.length === 0 || segments.some((s) => s === "" || s === "." || s === "..")) {
    return null;
  }
  if (TOKEN_PATHS.some((pattern) => pattern.test(segments.join("/")))) return null;
  return `/${segments.map(encodeURIComponent).join("/")}${search}`;
}

export function upstreamRequestHeaders(incoming: Headers, device: string): Headers {
  const headers = new Headers(incoming);
  for (const name of DROP_REQUEST) headers.delete(name);
  for (const name of [...headers.keys()]) if (name.startsWith("sec-")) headers.delete(name);
  headers.set("user-agent", incoming.get("user-agent") ?? device);
  headers.set("x-sparky-client", "web");
  return headers;
}

export function downstreamHeaders(upstream: Headers): Headers {
  const headers = new Headers(upstream);
  for (const name of DROP_RESPONSE) headers.delete(name);
  if (headers.has("content-encoding")) {
    for (const name of DECODED_BODY_HEADERS) headers.delete(name);
  }
  if (headers.get("content-type")?.startsWith("text/event-stream")) {
    headers.set("cache-control", "no-cache, no-transform");
    headers.set("x-accel-buffering", "no");
  }
  return headers;
}

export async function proxyRequest(
  req: Request,
  segments: string[],
  search: string,
  store: SessionStore,
  deps: UpstreamDeps,
): Promise<Response> {
  const path = upstreamPath(segments, search);
  if (!path) return jsonError(404, "not_found", "Not found.");
  const hasBody = !BODYLESS_METHODS.has(req.method) && req.body !== null;
  let upstream: Response;
  try {
    upstream = await apiFetch(
      path,
      {
        method: req.method,
        headers: upstreamRequestHeaders(req.headers, deps.device),
        body: hasBody ? req.body : null,
        signal: req.signal,
        replayable: !hasBody,
      },
      store,
      deps,
    );
  } catch {
    return req.signal.aborted ? new Response(null, { status: 499 }) : unreachable();
  }
  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers: downstreamHeaders(upstream.headers),
  });
}
