import { describe, expect, it } from "vitest";
import { cn } from "./cn";

describe("cn", () => {
  it("joins and drops falsy values", () => {
    expect(cn("a", false, undefined, "b")).toBe("a b");
  });

  it("lets the last conflicting utility win", () => {
    expect(cn("px-sm", "px-lg")).toBe("px-lg");
  });

  it("keeps custom font sizes next to text colors", () => {
    expect(cn("text-caption", "text-text-secondary")).toBe("text-caption text-text-secondary");
  });

  it("replaces a custom font size with a later one", () => {
    expect(cn("text-body", "text-headline")).toBe("text-headline");
  });
});
