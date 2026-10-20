import { afterEach, describe, expect, it, vi } from "vitest";
import { describeResult, statusLabel, statusTone } from "../lib/key-flow";
import { ApiError } from "./http";
import { fetchKeyUsage, removeKey, saveKey, testKey } from "./keys";

const STORED = {
  provider: "groq",
  label: "",
  hint: "a1B2",
  status: "valid",
  lastCheckedAt: "2026-10-20T10:00:00.000Z",
  createdAt: "2026-10-20T10:00:00.000Z",
};

const reply = (status: number, body?: unknown): Response =>
  new Response(body === undefined ? null : JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const mockFetch = (response: Response) => {
  const fn = vi.fn().mockResolvedValue(response);
  vi.stubGlobal("fetch", fn);
  return fn;
};

afterEach(() => vi.unstubAllGlobals());

describe("key test flow", () => {
  it("saves a key through the proxy and reads the live check result", async () => {
    const fetchMock = mockFetch(reply(200, { key: STORED, result: "valid", message: "Works" }));
    const saved = await saveKey("groq", "gsk_secret");
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("/api/sparky/me/keys/groq");
    expect(init.method).toBe("PUT");
    expect(JSON.parse(String(init.body))).toEqual({ key: "gsk_secret" });
    expect(saved.result).toBe("valid");
    expect(describeResult(saved.result).tone).toBe("ok");
  });

  it("tests a stored key with POST and no body", async () => {
    const fetchMock = mockFetch(
      reply(200, {
        provider: "groq",
        status: "quota",
        result: "quota",
        message: "Out of credit",
        checkedAt: null,
      }),
    );
    const tested = await testKey("groq");
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("/api/sparky/me/keys/groq/test");
    expect(init.method).toBe("POST");
    expect(init.body).toBeUndefined();
    expect(describeResult(tested.result)).toEqual({ tone: "warn", message: "Out of credit" });
  });

  it("surfaces the server message when a key is rejected", async () => {
    mockFetch(
      reply(400, { error: { code: "bad_request", message: "That doesn't look like a Groq key." } }),
    );
    await expect(saveKey("groq", "nope")).rejects.toMatchObject({
      status: 400,
      message: "That doesn't look like a Groq key.",
    });
  });

  it("falls back to a plain message when the error body is not JSON", async () => {
    mockFetch(new Response("<html>", { status: 502 }));
    const error = await testKey("groq").catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect((error as ApiError).message).toBe("Something went wrong. Try again.");
  });

  it("removes a key with DELETE and accepts an empty answer", async () => {
    const fetchMock = mockFetch(reply(200, { ok: true }));
    await expect(removeKey("groq")).resolves.toBeUndefined();
    expect((fetchMock.mock.calls[0] as [string, RequestInit])[1].method).toBe("DELETE");
  });

  it("asks for usage over the chosen window", async () => {
    const fetchMock = mockFetch(
      reply(200, {
        enabled: false,
        days: 30,
        totals: {
          requests: 0,
          errors: 0,
          promptTokens: 0,
          completionTokens: 0,
          tokens: 0,
          avgLatencyMs: null,
        },
        byDay: [],
        byProvider: [],
        byModel: [],
      }),
    );
    await fetchKeyUsage(30);
    expect((fetchMock.mock.calls[0] as [string])[0]).toBe("/api/sparky/me/usage/keys?days=30");
  });
});

describe("key status helpers", () => {
  it("maps results and statuses to tones and labels", () => {
    expect(describeResult("invalid").tone).toBe("bad");
    expect(describeResult("network").tone).toBe("neutral");
    expect(statusTone("untested")).toBe("neutral");
    expect(statusLabel("valid")).toBe("Works");
  });
});
