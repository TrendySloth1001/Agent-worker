// @vitest-environment node
import { describe, expect, it } from "vitest";
import { csrfGuard, isSameOrigin } from "./csrf";

const headers = (init: Record<string, string>) => new Headers(init);

describe("isSameOrigin", () => {
  it("trusts Sec-Fetch-Site: same-origin and nothing else when present", () => {
    expect(isSameOrigin(headers({ "sec-fetch-site": "same-origin" }))).toBe(true);
    expect(
      isSameOrigin(
        headers({ "sec-fetch-site": "cross-site", origin: "https://app.test", host: "app.test" }),
      ),
    ).toBe(false);
    expect(isSameOrigin(headers({ "sec-fetch-site": "same-site" }))).toBe(false);
    expect(isSameOrigin(headers({ "sec-fetch-site": "none" }))).toBe(false);
  });

  it("falls back to Origin matching the host", () => {
    expect(isSameOrigin(headers({ origin: "https://app.test", host: "app.test" }))).toBe(true);
    expect(
      isSameOrigin(
        headers({
          origin: "https://app.test",
          "x-forwarded-host": "app.test",
          host: "internal:3000",
        }),
      ),
    ).toBe(true);
    expect(isSameOrigin(headers({ origin: "https://evil.test", host: "app.test" }))).toBe(false);
  });

  it("accepts the configured app origin", () => {
    expect(
      isSameOrigin(
        headers({ origin: "https://app.test", host: "internal:3000" }),
        "https://app.test",
      ),
    ).toBe(true);
  });

  it("rejects a missing or malformed Origin", () => {
    expect(isSameOrigin(headers({ host: "app.test" }))).toBe(false);
    expect(isSameOrigin(headers({ origin: "not a url", host: "app.test" }))).toBe(false);
    expect(isSameOrigin(headers({ origin: "null", host: "app.test" }))).toBe(false);
  });
});

describe("csrfGuard", () => {
  const request = (method: string, init: Record<string, string> = {}) =>
    new Request("https://app.test/api/x", { method, headers: init });

  it("lets safe methods through without checks", () => {
    expect(csrfGuard(request("GET"))).toBeNull();
    expect(csrfGuard(request("HEAD"))).toBeNull();
  });

  it("blocks unsafe cross-origin requests with 403", async () => {
    const res = csrfGuard(request("POST", { origin: "https://evil.test", host: "app.test" }));
    expect(res?.status).toBe(403);
    expect(await res?.json()).toMatchObject({ error: { code: "forbidden_origin" } });
  });

  it("allows same-origin unsafe requests", () => {
    expect(csrfGuard(request("DELETE", { "sec-fetch-site": "same-origin" }))).toBeNull();
    expect(
      csrfGuard(request("PATCH", { origin: "https://app.test", host: "app.test" })),
    ).toBeNull();
  });
});
