// @vitest-environment node
import { describe, expect, it, vi } from "vitest";
import { apiFetch } from "./api-fetch";
import type { UpstreamDeps } from "./refresh";
import { memorySessionStore } from "./testing/memory-session-store";

const API = "https://api.test";

const user = {
  id: "u",
  email: "a@b.co",
  name: "A",
  avatarUrl: null,
  role: "user",
  createdAt: "",
  lastLoginAt: null,
  hasPassword: true,
  onboarded: true,
};

const rotated = (n: number) => ({
  user,
  accessToken: `access-${n}`,
  accessExpiresAt: "2099-01-01T00:00:00Z",
  refreshToken: `refresh-${n}`,
  refreshExpiresAt: "2099-02-01T00:00:00Z",
});

type Handler = (url: string, init: RequestInit) => Response | Promise<Response>;

function setup(handler: Handler) {
  const calls: { url: string; auth: string | null; body: unknown }[] = [];
  const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, auth: new Headers(init?.headers).get("authorization"), body: init?.body });
    return handler(url, init ?? {});
  });
  const deps: UpstreamDeps = {
    apiUrl: API,
    fetch: fetchMock as typeof fetch,
    device: "sparky web",
  };
  const refreshCalls = () => calls.filter((c) => c.url.endsWith("/auth/refresh")).length;
  return { calls, deps, refreshCalls };
}

const isRefresh = (url: string) => url.endsWith("/auth/refresh");
let counter = 0;
const uniqueRefreshToken = () => `rt-${(counter += 1)}`;

describe("apiFetch", () => {
  it("attaches the bearer token", async () => {
    const { deps, calls } = setup(() => Response.json({ ok: true }));
    const { store } = memorySessionStore({
      accessToken: "tok",
      refreshToken: uniqueRefreshToken(),
    });
    const res = await apiFetch("/things", {}, store, deps);
    expect(res.status).toBe(200);
    expect(calls).toEqual([{ url: `${API}/things`, auth: "Bearer tok", body: null }]);
  });

  it("refreshes first when only the refresh cookie is left, and rotates cookies", async () => {
    const rt = uniqueRefreshToken();
    const { deps, calls } = setup((url) =>
      isRefresh(url) ? Response.json(rotated(1)) : Response.json({ ok: true }),
    );
    const { store, writes } = memorySessionStore({ refreshToken: rt });
    const res = await apiFetch("/things", {}, store, deps);
    expect(res.status).toBe(200);
    expect(calls.map((c) => c.auth)).toEqual([null, "Bearer access-1"]);
    expect(JSON.parse(String(calls[0]?.body))).toMatchObject({
      refreshToken: rt,
      device: "sparky web",
    });
    expect(writes).toHaveLength(1);
    expect(store.read()).toEqual({ accessToken: "access-1", refreshToken: "refresh-1" });
  });

  it("refreshes once on 401 and replays the request", async () => {
    const { deps, calls } = setup((url, init) => {
      if (isRefresh(url)) return Response.json(rotated(2));
      const auth = new Headers(init.headers).get("authorization");
      return auth === "Bearer access-2"
        ? Response.json({ ok: true })
        : new Response(null, { status: 401 });
    });
    const { store } = memorySessionStore({
      accessToken: "stale",
      refreshToken: uniqueRefreshToken(),
    });
    const res = await apiFetch("/things", {}, store, deps);
    expect(res.status).toBe(200);
    expect(calls.map((c) => c.url)).toEqual([
      `${API}/things`,
      `${API}/auth/refresh`,
      `${API}/things`,
    ]);
  });

  it("does not loop when the refreshed token is also rejected", async () => {
    const { deps, refreshCalls } = setup((url) =>
      isRefresh(url) ? Response.json(rotated(3)) : new Response(null, { status: 401 }),
    );
    const { store } = memorySessionStore({
      accessToken: "stale",
      refreshToken: uniqueRefreshToken(),
    });
    const res = await apiFetch("/things", {}, store, deps);
    expect(res.status).toBe(401);
    expect(refreshCalls()).toBe(1);
  });

  it("shares one refresh between concurrent requests", async () => {
    let release: () => void = () => undefined;
    const gate = new Promise<void>((resolve) => (release = resolve));
    const { deps, refreshCalls } = setup(async (url) => {
      if (isRefresh(url)) {
        await gate;
        return Response.json(rotated(4));
      }
      return Response.json({ ok: true });
    });
    const rt = uniqueRefreshToken();
    const stores = Array.from({ length: 5 }, () => memorySessionStore({ refreshToken: rt }));
    const pending = stores.map(({ store }) => apiFetch("/things", {}, store, deps));
    release();
    const responses = await Promise.all(pending);
    expect(responses.every((r) => r.status === 200)).toBe(true);
    expect(refreshCalls()).toBe(1);
    for (const { writes } of stores) expect(writes).toHaveLength(1);
  });

  it("clears the session when the refresh token is rejected", async () => {
    const { deps } = setup(() => new Response(null, { status: 401 }));
    const { store, cleared } = memorySessionStore({
      accessToken: "stale",
      refreshToken: uniqueRefreshToken(),
    });
    const res = await apiFetch("/things", {}, store, deps);
    expect(res.status).toBe(401);
    expect(cleared()).toBe(1);
  });

  it("keeps the session when the refresh endpoint is down", async () => {
    const { deps } = setup((url) => new Response(null, { status: isRefresh(url) ? 503 : 401 }));
    const { store, cleared } = memorySessionStore({
      accessToken: "stale",
      refreshToken: uniqueRefreshToken(),
    });
    await apiFetch("/things", {}, store, deps);
    expect(cleared()).toBe(0);
    expect(store.read().refreshToken).not.toBeNull();
  });

  it("does not replay a one-shot body after refreshing", async () => {
    const { deps, calls } = setup((url) =>
      isRefresh(url) ? Response.json(rotated(5)) : new Response(null, { status: 401 }),
    );
    const { store, writes } = memorySessionStore({
      accessToken: "stale",
      refreshToken: uniqueRefreshToken(),
    });
    const res = await apiFetch(
      "/upload",
      { method: "POST", body: "x", replayable: false },
      store,
      deps,
    );
    expect(res.status).toBe(401);
    expect(writes).toHaveLength(1);
    expect(calls.filter((c) => c.url.endsWith("/upload"))).toHaveLength(1);
  });

  it("never refreshes where cookies cannot be written", async () => {
    const { deps, calls } = setup(() => new Response(null, { status: 401 }));
    const { store } = memorySessionStore({
      accessToken: "stale",
      refreshToken: uniqueRefreshToken(),
    });
    const res = await apiFetch("/auth/me", { refresh: false }, store, deps);
    expect(res.status).toBe(401);
    expect(calls).toHaveLength(1);
  });
});
