import { describe, expect, it } from "vitest";
import { checkFile, classifyFile, formatBytes } from "./limits";
import { previewTypeOf } from "./preview-type";

const MB = 1024 * 1024;

describe("limits", () => {
  it("classifies by extension first, then mime", () => {
    expect(classifyFile("a.PNG", "")).toBe("image");
    expect(classifyFile("a.mp3", "application/octet-stream")).toBe("audio");
    expect(classifyFile("noext", "video/mp4")).toBe("video");
    expect(classifyFile("a.exe", "application/x-msdownload")).toBeNull();
  });

  it("applies the per-kind size limits from the app", () => {
    expect(checkFile({ name: "a.jpg", type: "image/jpeg", size: 15 * MB }).error).toBeNull();
    expect(checkFile({ name: "a.jpg", type: "image/jpeg", size: 15 * MB + 1 }).error).toMatch(
      /Image files can be at most 15 MB/,
    );
    expect(checkFile({ name: "a.pdf", type: "application/pdf", size: 26 * MB }).error).toMatch(
      /25 MB/,
    );
    expect(checkFile({ name: "a.mp4", type: "video/mp4", size: 100 * MB }).error).toBeNull();
    expect(checkFile({ name: "a.mp4", type: "video/mp4", size: 0 }).error).toMatch(/empty/);
    expect(checkFile({ name: "a.exe", type: "", size: 5 }).error).toMatch(/can't open/);
  });

  it("formats sizes", () => {
    expect(formatBytes(512)).toBe("512 B");
    expect(formatBytes(2048)).toBe("2.0 KB");
    expect(formatBytes(5 * MB)).toBe("5.0 MB");
  });

  it("picks the preview viewer", () => {
    expect(previewTypeOf({ kind: "document", name: "a.pdf", mime: "application/pdf" })).toBe("pdf");
    expect(previewTypeOf({ kind: "document", name: "a.docx", mime: "" })).toBe("office");
    expect(previewTypeOf({ kind: "document", name: "a.md", mime: "text/markdown" })).toBe("text");
    expect(previewTypeOf({ kind: "video", name: "a.mp4", mime: "video/mp4" })).toBe("video");
  });
});
