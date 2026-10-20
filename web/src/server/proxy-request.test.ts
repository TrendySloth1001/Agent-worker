// @vitest-environment node
import { describe, expect, it } from "vitest";
import type { UpstreamDeps } from "./refresh";
import {
  downstreamHeaders,
  proxyRequest,
  upstreamPath,
  upstreamRequestHeaders,
} from "./proxy-request";
import { memorySessionStore } from "./testing/memory-session-store";

describe("upstreamPath", () => {
  it("maps segments and keeps the query string", () => {
    expect(upstreamPath(["conversations", "a b"], "?limit=5")).toBe("/conversations/a%20b?limit=5");
  });

  it("rejects empty and traversal segments", () => {
    expect(upstreamPath([], "")).toBeNull();
    expect(upstreamPath(["files", "..", "auth"], "")).toBeNull();
    expect(upstreamPath(["files", ""], "")).toBeNull();
  });

  it("refuses endpoints whose responses carry session tokens", () => {
    const blocked = [
      ["auth", "login"],
      ["auth", "register"],
      ["auth", "refresh"],
      ["auth", "logout"],
      ["auth", "google"],
      ["auth", "github", "web", "redeem"],
      ["auth", "github", "device"],
    ];
    for (const path of blocked) expect(upstreamPath(path, "")).toBeNull();
    expect(upstreamPath(["auth", "me"], "")).toBe("/auth/me");
    expect(upstreamPath(["auth", "sessions"], "")).toBe("/auth/sessions");
  });
});

describe("headers", () => {
  it("drops hop-by-hop, credential and forwarding headers from the request", () => {
    const out = upstreamRequestHeaders(
      new Headers({
        connection: "keep-alive",
        cookie: "sparky_at=secret",
        authorization: "Bearer browser",
        origin: "https://app.test",
        "sec-fetch-site": "same-origin",
        "x-forwarded-for": "1.2.3.4",
        expect: "100-continue",
        "content-type": "multipart/form-data; boundary=abc",
        "last-event-id": "7",
        "user-agent": "Mozilla/5.0 Test",
      }),
      "sparky web",
    );
    expect([...out.keys()].sort()).toEqual([
      "content-type",
      "last-event-id",
      "user-agent",
      "x-sparky-client",
    ]);
    expect(out.get("user-agent")).toBe("Mozilla/5.0 Test");
  });

  it("falls back to the device label when the browser sent no user agent", () => {
    expect(upstreamRequestHeaders(new Headers(), "sparky web · Chrome").get("user-agent")).toBe(
      "sparky web · Chrome",
    );
  });

  it("strips hop-by-hop and set-cookie from the response and disables buffering for SSE", () => {
    const out = downstreamHeaders(
      new Headers({
        connection: "close",
        "transfer-encoding": "chunked",
        "set-cookie": "a=b",
        "content-type": "text/event-stream",
        "content-encoding": "gzip",
        "content-length": "10",
      }),
    );
    expect(out.has("connection") || out.has("transfer-encoding") || out.has("set-cookie")).toBe(
      false,
    );
    expect(out.has("content-encoding") || out.has("content-length")).toBe(false);
    expect(out.get("x-accel-buffering")).toBe("no");
    expect(out.get("cache-control")).toContain("no-transform");
  });
});

describe("proxyRequest", () => {
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  it("streams the response body as it arrives, without buffering", async () => {
    let push: (chunk: string) => void = () => undefined;
    let finish: () => void = () => undefined;
    const upstreamBody = new ReadableStream<Uint8Array>({
      start(controller) {
        push = (chunk) => controller.enqueue(encoder.encode(chunk));
        finish = () => controller.close();
      },
    });
    const deps: UpstreamDeps = {
      apiUrl: "https://api.test",
      device: "sparky web",
      fetch: (async () =>
        new Response(upstreamBody, {
          headers: { "content-type": "text/event-stream" },
        })) as typeof fetch,
    };
    const { store } = memorySessionStore({ accessToken: "tok" });
    const res = await proxyRequest(
      new Request("https://app.test/api/sparky/chat"),
      ["chat"],
      "",
      store,
      deps,
    );
    expect(res.headers.get("content-type")).toBe("text/event-stream");
    const reader = res.body!.getReader();
    push("data: one\n\n");
    expect(decoder.decode((await reader.read()).value)).toBe("data: one\n\n");
    push("data: two\n\n");
    expect(decoder.decode((await reader.read()).value)).toBe("data: two\n\n");
    finish();
    expect((await reader.read()).done).toBe(true);
  });

  it("passes the request body through as a stream and forwards abort", async () => {
    let seen:
      | { body: unknown; signal: AbortSignal | null | undefined; method: string | undefined }
      | undefined;
    const deps: UpstreamDeps = {
      apiUrl: "https://api.test",
      device: "sparky web",
      fetch: (async (_url: RequestInfo | URL, init?: RequestInit) => {
        seen = { body: init?.body, signal: init?.signal, method: init?.method };
        return new Response("done");
      }) as typeof fetch,
    };
    const controller = new AbortController();
    const req = new Request("https://app.test/api/sparky/files", {
      method: "POST",
      body: new Uint8Array([1, 2, 3]),
      headers: { "content-type": "application/octet-stream" },
      signal: controller.signal,
    });
    const { store } = memorySessionStore({ accessToken: "tok" });
    await proxyRequest(req, ["files"], "", store, deps);
    expect(seen?.method).toBe("POST");
    expect(seen?.body).toBeInstanceOf(ReadableStream);
    controller.abort();
    expect(seen?.signal?.aborted).toBe(true);
  });

  it("answers 404 for blocked paths without calling upstream", async () => {
    const deps: UpstreamDeps = {
      apiUrl: "https://api.test",
      device: "d",
      fetch: (async () => {
        throw new Error("called");
      }) as typeof fetch,
    };
    const { store } = memorySessionStore({ accessToken: "tok" });
    const res = await proxyRequest(
      new Request("https://app.test/x", { method: "POST" }),
      ["auth", "login"],
      "",
      store,
      deps,
    );
    expect(res.status).toBe(404);
  });

  it("returns 502 when the API is unreachable", async () => {
    const deps: UpstreamDeps = {
      apiUrl: "https://api.test",
      device: "d",
      fetch: (async () => {
        throw new TypeError("fetch failed");
      }) as typeof fetch,
    };
    const { store } = memorySessionStore({ accessToken: "tok" });
    const res = await proxyRequest(new Request("https://app.test/x"), ["health"], "", store, deps);
    expect(res.status).toBe(502);
    expect(await res.json()).toMatchObject({ error: { code: "upstream_unreachable" } });
  });
});
