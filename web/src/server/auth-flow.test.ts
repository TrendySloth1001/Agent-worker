// @vitest-environment node
import { describe, expect, it } from "vitest";
import { loginInputSchema } from "@/lib/api/schemas";
import { exchangeCredentials } from "./auth-flow";
import type { UpstreamDeps } from "./refresh";
import { memorySessionStore } from "./testing/memory-session-store";

const session = {
  user: {
    id: "u1",
    email: "a@b.co",
    name: "Ada",
    avatarUrl: null,
    role: "user",
    createdAt: "",
    lastLoginAt: null,
    hasPassword: true,
    onboarded: false,
  },
  accessToken: "access-secret",
  accessExpiresAt: "2099-01-01T00:00:00Z",
  refreshToken: "refresh-secret",
  refreshExpiresAt: "2099-02-01T00:00:00Z",
  sessionId: "s1",
};

const sameOrigin = { "sec-fetch-site": "same-origin" };
const post = (body: unknown, headers: Record<string, string> = sameOrigin) =>
  new Request("https://app.test/api/auth/login", {
    method: "POST",
    body: JSON.stringify(body),
    headers,
  });

const depsWith = (respond: () => Response): UpstreamDeps => ({
  apiUrl: "https://api.test",
  device: "sparky web · Chrome on macOS",
  fetch: (async () => respond()) as typeof fetch,
});

const login = (
  req: Request,
  store: ReturnType<typeof memorySessionStore>["store"],
  deps: UpstreamDeps,
) => exchangeCredentials(req, loginInputSchema, "/auth/login", store, deps);

describe("exchangeCredentials", () => {
  it("stores tokens in cookies and returns only the user", async () => {
    const { store, writes } = memorySessionStore();
    const res = await login(
      post({ email: "a@b.co", password: "pw" }),
      store,
      depsWith(() => Response.json(session)),
    );
    expect(res.status).toBe(200);
    const text = await res.text();
    expect(JSON.parse(text)).toEqual({ user: session.user });
    expect(text).not.toContain("secret");
    expect(writes[0]).toMatchObject({
      accessToken: "access-secret",
      refreshToken: "refresh-secret",
    });
  });

  it("sends the device label upstream", async () => {
    let sent: unknown;
    const deps: UpstreamDeps = {
      apiUrl: "https://api.test",
      device: "sparky web · Chrome on macOS",
      fetch: (async (_url: RequestInfo | URL, init?: RequestInit) => {
        sent = JSON.parse(String(init?.body));
        return Response.json(session);
      }) as typeof fetch,
    };
    await login(post({ email: "a@b.co", password: "pw" }), memorySessionStore().store, deps);
    expect(sent).toEqual({
      email: "a@b.co",
      password: "pw",
      device: "sparky web · Chrome on macOS",
    });
  });

  it("passes upstream errors through without touching cookies", async () => {
    const { store, writes, cleared } = memorySessionStore();
    const res = await login(
      post({ email: "a@b.co", password: "wrong" }),
      store,
      depsWith(() =>
        Response.json(
          { error: { code: "invalid_credentials", message: "Wrong email or password" } },
          { status: 401 },
        ),
      ),
    );
    expect(res.status).toBe(401);
    expect(await res.json()).toEqual({
      error: { code: "invalid_credentials", message: "Wrong email or password" },
    });
    expect(writes).toHaveLength(0);
    expect(cleared()).toBe(0);
  });

  it("rejects cross-origin posts before calling upstream", async () => {
    const deps = depsWith(() => {
      throw new Error("called");
    });
    const res = await login(
      post({ email: "a@b.co", password: "pw" }, { origin: "https://evil.test", host: "app.test" }),
      memorySessionStore().store,
      deps,
    );
    expect(res.status).toBe(403);
  });

  it("rejects malformed input with 400", async () => {
    const res = await login(
      post({ email: "" }),
      memorySessionStore().store,
      depsWith(() => Response.json(session)),
    );
    expect(res.status).toBe(400);
  });
});
