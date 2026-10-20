import { describe, expect, it } from "vitest";
import { guardRoute } from "./route-guard";
import { safeNext } from "./safe-next";

describe("guardRoute", () => {
  it("sends signed-out visitors of app routes through the session refresh", () => {
    expect(guardRoute("/chat", "?id=3", false)).toEqual({
      action: "redirect",
      location: "/api/auth/session?next=%2Fchat%3Fid%3D3",
    });
  });

  it("lets signed-in users through and keeps public pages open", () => {
    expect(guardRoute("/chat", "", true)).toEqual({ action: "next" });
    expect(guardRoute("/", "", false)).toEqual({ action: "next" });
    expect(guardRoute("/ui/forms", "", false)).toEqual({ action: "next" });
    expect(guardRoute("/login", "", false)).toEqual({ action: "next" });
  });

  it("moves signed-in users off /login to a safe next", () => {
    expect(guardRoute("/login", "?next=%2Fsettings", true)).toEqual({
      action: "redirect",
      location: "/settings",
    });
    expect(guardRoute("/login", "?next=https%3A%2F%2Fevil.test", true)).toEqual({
      action: "redirect",
      location: "/chat",
    });
    expect(guardRoute("/login", "", true)).toEqual({ action: "redirect", location: "/chat" });
  });
});

describe("safeNext", () => {
  it("only accepts same-site absolute paths", () => {
    expect(safeNext("/settings?tab=1")).toBe("/settings?tab=1");
    for (const bad of [
      "//evil.test",
      "https://evil.test",
      "evil",
      "/\\evil",
      "",
      null,
      undefined,
    ]) {
      expect(safeNext(bad)).toBe("/chat");
    }
  });
});
