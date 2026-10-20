import { describe, expect, it } from "vitest";
import { resolveWait } from "./wait-status";

const base = { waitLast: undefined, phase: "", modelId: undefined, attempt: 1, candidates: [] };
const nameOf = (id: string) => (id === "unknown" ? null : id.toUpperCase());

describe("resolveWait", () => {
  it("thinks when nothing is known", () => {
    expect(resolveWait(base, nameOf).kind).toBe("think");
  });

  it("explains known phases and falls back to thinking for generating", () => {
    expect(resolveWait({ ...base, waitLast: "status", phase: "searching" }, nameOf).text).toBe("Searching the web…");
    expect(resolveWait({ ...base, waitLast: "status", phase: "generating" }, nameOf).kind).toBe("think");
  });

  it("announces the chosen model and a switch, never a raw id", () => {
    expect(resolveWait({ ...base, waitLast: "model", modelId: "a" }, nameOf).text).toBe("Going with A");
    expect(resolveWait({ ...base, waitLast: "model", modelId: "a", attempt: 2 }, nameOf).kind).toBe("switching");
    expect(resolveWait({ ...base, waitLast: "model", modelId: "unknown" }, nameOf).kind).toBe("think");
  });

  it("shows up to three distinct candidates while picking", () => {
    const step = resolveWait({ ...base, waitLast: "start", candidates: ["a", "a", "b", "c", "d"] }, nameOf);
    expect(step.modelIds).toEqual(["a", "b", "c"]);
  });
});
