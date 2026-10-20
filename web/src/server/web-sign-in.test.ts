// @vitest-environment node
import { describe, expect, it } from "vitest";
import { decodeFlow, encodeFlow } from "./web-sign-in";

describe("flow cookie", () => {
  it("round-trips the state and next path", () => {
    expect(decodeFlow(encodeFlow({ state: "abc.def", next: "/chat?x=1|2" }))).toEqual({
      state: "abc.def",
      next: "/chat?x=1|2",
    });
  });

  it("falls back to a safe next and rejects garbage", () => {
    expect(decodeFlow(encodeFlow({ state: "s", next: "//evil.test" }))?.next).toBe("/chat");
    expect(decodeFlow(undefined)).toBeNull();
    expect(decodeFlow("nostate")).toBeNull();
  });
});
