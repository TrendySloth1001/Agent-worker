import { describe, expect, it } from "vitest";
import { evaluate } from "./calc-eval";
import { resolveIntent } from "./intent";
import { safeActionUrl, safeWebUrl } from "./safe-url";

describe("safe urls", () => {
  it("allows only http(s) for web links", () => {
    expect(safeWebUrl("https://example.com/a?b=1")).toBe("https://example.com/a?b=1");
    expect(safeWebUrl("javascript:alert(1)")).toBeNull();
    expect(safeWebUrl("data:text/html,<script>")).toBeNull();
    expect(safeWebUrl("//evil.com")).toBeNull();
    expect(safeWebUrl("https://ex\nample.com")).toBeNull();
    expect(safeWebUrl(undefined)).toBeNull();
  });

  it("allows an explicit list of action schemes", () => {
    expect(safeActionUrl("tel:+911234567890")).toBe("tel:+911234567890");
    expect(safeActionUrl("mailto:a@b.co")).toBe("mailto:a@b.co");
    expect(safeActionUrl("intent://scan#Intent;end")).toBeNull();
    expect(safeActionUrl("file:///etc/passwd")).toBeNull();
  });
});

describe("card intents", () => {
  it("maps navigation, calls and sms to links", () => {
    expect(resolveIntent({ action: "view", uri: "google.navigation:q=Cafe%20X" })).toEqual({
      kind: "link",
      href: "https://www.google.com/maps/dir/?api=1&destination=Cafe%20X",
    });
    expect(resolveIntent({ action: "dial", uri: "tel:+9112345" })).toEqual({
      kind: "link",
      href: "tel:+9112345",
    });
    expect(
      resolveIntent({ action: "sendto", uri: "smsto:+9112345", extras: { body: "hi there" } }),
    ).toEqual({
      kind: "link",
      href: "sms:+9112345?body=hi%20there",
    });
  });

  it("falls back to an https link and drops unsafe uris", () => {
    expect(
      resolveIntent({
        action: "view",
        uri: "javascript:alert(1)",
        fallback: "https://www.google.com/",
      }),
    ).toEqual({
      kind: "link",
      href: "https://www.google.com/",
    });
    expect(resolveIntent({ action: "view", uri: "javascript:alert(1)" })).toBeNull();
  });

  it("builds a calendar link, a vcard and share text", () => {
    const event = resolveIntent({
      action: "insert_event",
      extras: { title: "Dentist", begin: "2026-10-23T16:00" },
    });
    expect(event).toMatchObject({ kind: "link" });
    expect(event?.kind === "link" && event.href).toContain("dates=20261023T160000/20261023T160000");
    expect(
      resolveIntent({ action: "insert_contact", extras: { name: "Asha", phone: "+911" } }),
    ).toMatchObject({
      kind: "download",
      filename: "Asha.vcf",
    });
    expect(resolveIntent({ action: "send", extras: { text: "hello" } })).toEqual({
      kind: "copy",
      text: "hello",
    });
  });
});

describe("calculator expressions", () => {
  it("evaluates operators, precedence, functions and variables", () => {
    expect(evaluate("2 + 3 * 4", {})).toBe(14);
    expect(evaluate("2^3^2", {})).toBe(512);
    expect(evaluate("-(a + 1) * 2", { a: 2 })).toBe(-6);
    expect(evaluate("max(1, sqrt(16), 3) + pi * 0", {})).toBe(4);
    expect(evaluate("principal*(rate/1200)", { principal: 12000, rate: 12 })).toBe(120);
  });

  it("returns null for invalid or unsafe input", () => {
    expect(evaluate("1 +", {})).toBeNull();
    expect(evaluate("unknown + 1", {})).toBeNull();
    expect(evaluate("1 / 0", {})).toBeNull();
    expect(evaluate("alert(1)", {})).toBeNull();
    expect(evaluate("constructor", {})).toBeNull();
    expect(evaluate("1; 2", {})).toBeNull();
  });
});

describe("parseDeviceAction", () => {
  it("maps phone actions to web equivalents", async () => {
    const { parseDeviceAction } = await import("../parsers/device-action");
    const url = parseDeviceAction(
      '{"type": "url", "url": "https://www.google.com/travel/flights", "app": "Chrome"}',
    );
    expect(url).toMatchObject({
      kind: "link",
      href: "https://www.google.com/travel/flights",
      title: "Chrome",
    });
    expect(
      parseDeviceAction('{"type":"navigate","destination":"Lonavala","travel":"drive"}'),
    ).toMatchObject({
      kind: "link",
      href: "https://www.google.com/maps/dir/?api=1&destination=Lonavala&travelmode=driving",
    });
    expect(parseDeviceAction('{"type":"alarm","time":"07:00"}')).toMatchObject({
      kind: "phone",
      title: "07:00",
    });
    expect(parseDeviceAction('{"type":"url","url":"javascript:alert(1)"}')).toBeNull();
  });
});
