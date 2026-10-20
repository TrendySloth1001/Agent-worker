import "server-only";
import { refreshSession, type UpstreamDeps } from "./refresh";
import type { SessionStore } from "./session-store";

type StreamingRequestInit = RequestInit & { duplex: "half" };

export interface ApiFetchInit {
  method?: string;
  headers?: Headers;
  body?: BodyInit | null;
  signal?: AbortSignal;
  /** False for a one-shot stream: after a 401 the request cannot be sent again. */
  replayable?: boolean;
  /** False where cookies cannot be written (Server Components). */
  refresh?: boolean;
}

export async function apiFetch(
  path: string,
  init: ApiFetchInit,
  store: SessionStore,
  deps: UpstreamDeps,
): Promise<Response> {
  const { replayable = true, refresh = true } = init;
  let { accessToken } = store.read();
  let refreshed = false;

  if (!accessToken && refresh) {
    refreshed = true;
    accessToken = (await refreshSession(store, deps))?.accessToken ?? null;
  }

  const send = (token: string | null) => {
    const headers = new Headers(init.headers);
    if (token) headers.set("authorization", `Bearer ${token}`);
    const options: StreamingRequestInit = {
      method: init.method ?? "GET",
      headers,
      body: init.body ?? null,
      signal: init.signal,
      redirect: "manual",
      cache: "no-store",
      duplex: "half",
    };
    return deps.fetch(`${deps.apiUrl}${path}`, options);
  };

  const first = await send(accessToken);
  if (first.status !== 401 || !refresh || refreshed) return first;

  const tokens = await refreshSession(store, deps);
  if (!tokens || !replayable) return first;
  await first.body?.cancel();
  return send(tokens.accessToken);
}
