import { describe, expect, it } from "vitest";
import { prettyModelName } from "./pretty-model-name";

describe("prettyModelName", () => {
  it("drops provider prefixes, tags and variant noise", () => {
    expect(prettyModelName("meta-llama/llama-4-scout-17b-16e-instruct")).toBe("Llama 4 Scout 17B");
    expect(prettyModelName("openai/gpt-oss-120b:free")).toBe("GPT OSS 120B");
  });

  it("strips date stamps and formats sizes", () => {
    expect(prettyModelName("qwen3-8b-2507")).toBe("Qwen3 8B 2507");
    expect(prettyModelName("deepseek-r1-20250120")).toBe("DeepSeek R1");
    expect(prettyModelName("mixtral-8x7b")).toBe("Mixtral 8x7B");
  });

  it("returns an empty string for an empty id and caps the length", () => {
    expect(prettyModelName("  ")).toBe("");
    expect(prettyModelName("a-b-c-d-e-f").split(" ")).toHaveLength(4);
  });
});
