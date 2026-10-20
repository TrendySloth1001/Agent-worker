import { describe, expect, it } from "vitest";
import { DEFAULT_PREFERENCES, preferencesSchema } from "../preferences/schema";
import { parsePreferences } from "../preferences/store";
import { nameSchema, passwordChangeSchema } from "./account";
import { connectionsSchema, devicePollSchema } from "./connections";
import { keyInputSchema, keysSchema, keyUsageSchema } from "./keys";
import { memoryDraftSchema, memoryListSchema } from "./memory";
import { isSourceActive, noteDraftSchema, sourceInputSchema } from "./knowledge";

describe("account schemas", () => {
  it("trims names and rejects empty or long ones", () => {
    expect(nameSchema.parse("  Nikhil ")).toBe("Nikhil");
    expect(nameSchema.safeParse("   ").success).toBe(false);
    expect(nameSchema.safeParse("x".repeat(61)).success).toBe(false);
  });

  it("requires a long enough new password but not a current one", () => {
    expect(passwordChangeSchema.safeParse({ next: "short" }).success).toBe(false);
    expect(passwordChangeSchema.safeParse({ next: "long-enough-1" }).success).toBe(true);
  });
});

describe("keys schemas", () => {
  it("parses the provider list the server sends", () => {
    const parsed = keysSchema.parse({
      hasValidKey: true,
      providers: [
        {
          id: "groq",
          name: "Groq",
          blurb: "Very fast open models.",
          keyUrl: "https://console.groq.com/keys",
          placeholder: "gsk_…",
          key: {
            provider: "groq",
            label: "",
            hint: "a1B2",
            status: "valid",
            lastCheckedAt: null,
            createdAt: "2026-10-18T09:30:00.000Z",
          },
        },
      ],
    });
    expect(parsed.providers[0]?.key?.hint).toBe("a1B2");
  });

  it("rejects an unknown key status", () => {
    const bad = {
      provider: "groq",
      label: "",
      hint: "x",
      status: "weird",
      lastCheckedAt: null,
      createdAt: "",
    };
    expect(
      keysSchema.safeParse({
        hasValidKey: false,
        providers: [{ id: "g", name: "G", blurb: "", keyUrl: "", placeholder: "", key: bad }],
      }).success,
    ).toBe(false);
  });

  it("validates the pasted key", () => {
    expect(keyInputSchema.parse("  gsk_abc ")).toBe("gsk_abc");
    expect(keyInputSchema.safeParse("   ").success).toBe(false);
  });

  it("parses usage with nullable latency", () => {
    const usage = keyUsageSchema.parse({
      enabled: true,
      days: 7,
      totals: {
        requests: 1,
        errors: 0,
        promptTokens: 1,
        completionTokens: 1,
        tokens: 2,
        avgLatencyMs: null,
      },
      byDay: [{ day: "2026-10-20", requests: 1, tokens: 2, errors: 0 }],
      byProvider: [],
      byModel: [],
    });
    expect(usage.totals.avgLatencyMs).toBeNull();
  });
});

describe("memory schemas", () => {
  it("bounds the memory text", () => {
    expect(memoryDraftSchema.safeParse({ text: "a", kind: "fact" }).success).toBe(false);
    expect(memoryDraftSchema.safeParse({ text: "x".repeat(301), kind: "fact" }).success).toBe(
      false,
    );
    expect(memoryDraftSchema.parse({ text: " Likes tea ", kind: "preference" }).text).toBe(
      "Likes tea",
    );
  });

  it("parses the list payload", () => {
    const list = memoryListSchema.parse({
      enabled: true,
      chatRecall: false,
      total: 1,
      max: 500,
      items: [
        {
          id: "1",
          text: "t",
          kind: "fact",
          pinned: false,
          createdAt: "a",
          updatedAt: "b",
          slot: null,
        },
      ],
    });
    expect(list.items).toHaveLength(1);
  });
});

describe("knowledge and connections schemas", () => {
  it("requires a link and a note body", () => {
    expect(sourceInputSchema.safeParse("").success).toBe(false);
    expect(noteDraftSchema.safeParse({ title: "", content: " " }).success).toBe(false);
    expect(noteDraftSchema.safeParse({ title: "", content: "hello" }).success).toBe(true);
  });

  it("knows which sources are still being read", () => {
    expect(isSourceActive({ status: "queued" })).toBe(true);
    expect(isSourceActive({ status: "running" })).toBe(true);
    expect(isSourceActive({ status: "ready" })).toBe(false);
  });

  it("accepts the device flow statuses", () => {
    expect(devicePollSchema.parse({ status: "pending", interval: 5 }).status).toBe("pending");
    expect(devicePollSchema.safeParse({ status: "slow_down" }).success).toBe(false);
  });

  it("parses connections with provider availability", () => {
    const parsed = connectionsSchema.parse({
      items: [],
      providers: { github: { configured: true, web: false, extra: 1 } },
    });
    expect(parsed.providers.github?.configured).toBe(true);
  });
});

describe("preferences", () => {
  it("falls back to defaults for missing or corrupt storage", () => {
    expect(parsePreferences(null)).toEqual(DEFAULT_PREFERENCES);
    expect(parsePreferences("{not json")).toEqual(DEFAULT_PREFERENCES);
  });

  it("repairs single bad fields without losing the rest", () => {
    const parsed = parsePreferences(
      JSON.stringify({ tone: "friendly", length: "huge", textSize: 3 }),
    );
    expect(parsed.tone).toBe("friendly");
    expect(parsed.length).toBe("balanced");
    expect(parsed.textSize).toBe("normal");
  });

  it("round-trips a full object", () => {
    const full = { ...DEFAULT_PREFERENCES, model: "fast", mode: "debug" as const };
    expect(preferencesSchema.parse(full)).toEqual(full);
  });
});
