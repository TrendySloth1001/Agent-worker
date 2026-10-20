// @vitest-environment node
import { describe, expect, it } from "vitest";
import { deviceLabel } from "./device";

describe("deviceLabel", () => {
  it("names browser and system", () => {
    expect(
      deviceLabel(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126.0 Safari/537.36",
      ),
    ).toBe("sparky web · Chrome on macOS");
    expect(
      deviceLabel(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit Version/17.0 Safari/604.1",
      ),
    ).toBe("sparky web · Safari on iOS");
  });

  it("falls back to the bare prefix", () => {
    expect(deviceLabel(null)).toBe("sparky web");
  });
});
