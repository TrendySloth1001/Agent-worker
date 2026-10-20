import { describe, expect, it } from "vitest";
import { AVATAR_EDGE, fitWithin, fitsAvatarLimit, isAcceptedImage } from "./avatar-image";

describe("avatar image", () => {
  it("scales large images down keeping the ratio", () => {
    expect(fitWithin(1024, 512, AVATAR_EDGE)).toEqual({ width: 256, height: 128 });
  });

  it("never scales small images up", () => {
    expect(fitWithin(100, 80, AVATAR_EDGE)).toEqual({ width: 100, height: 80 });
  });

  it("accepts only the image types the server allows", () => {
    expect(isAcceptedImage("image/png")).toBe(true);
    expect(isAcceptedImage("image/gif")).toBe(false);
  });

  it("enforces the server size limit", () => {
    expect(fitsAvatarLimit("a".repeat(200_000))).toBe(true);
    expect(fitsAvatarLimit("a".repeat(200_001))).toBe(false);
  });
});
