import { describe, expect, it } from "vitest";
import { parseChatEvent } from "../schemas/events";
import { readSse, SseParser } from "./sse";

const streamOf = (...chunks: string[]): ReadableStream<Uint8Array> => {
  const encoder = new TextEncoder();
  return new ReadableStream({
    start(controller) {
      for (const c of chunks) controller.enqueue(encoder.encode(c));
      controller.close();
    },
  });
};

async function collect(stream: ReadableStream<Uint8Array>) {
  const out = [];
  for await (const m of readSse(stream)) out.push(m);
  return out;
}

describe("SseParser", () => {
  it("parses whole events", () => {
    const p = new SseParser();
    expect(p.push('event: delta\ndata: {"text":"a"}\n\nevent: done\ndata: {}\n\n')).toEqual([
      { event: "delta", data: '{"text":"a"}' },
      { event: "done", data: "{}" },
    ]);
  });

  it("handles events split at every position", () => {
    const raw = 'event: delta\ndata: {"text":"hi"}\n\n';
    for (let i = 1; i < raw.length; i++) {
      const p = new SseParser();
      const got = [...p.push(raw.slice(0, i)), ...p.push(raw.slice(i))];
      expect(got).toEqual([{ event: "delta", data: '{"text":"hi"}' }]);
    }
  });

  it("joins multi-line data with newlines", () => {
    const p = new SseParser();
    expect(p.push("event: x\ndata: one\ndata: two\n\n")).toEqual([
      { event: "x", data: "one\ntwo" },
    ]);
  });

  it("ignores comments and pings, accepts CRLF", () => {
    const p = new SseParser();
    expect(p.push(": ping\r\n\r\nevent: a\r\ndata: 1\r\n\r\n")).toEqual([
      { event: "a", data: "1" },
    ]);
  });

  it("defaults the event name and flushes an unterminated tail", () => {
    const p = new SseParser();
    expect(p.push("data: tail")).toEqual([]);
    expect(p.flush()).toEqual([{ event: "message", data: "tail" }]);
  });
});

describe("readSse", () => {
  it("decodes multi-byte characters split across chunks", async () => {
    const bytes = new TextEncoder().encode('event: delta\ndata: {"text":"é"}\n\n');
    const cut = bytes.indexOf(0xc3) + 1;
    const stream = new ReadableStream<Uint8Array>({
      start(c) {
        c.enqueue(bytes.slice(0, cut));
        c.enqueue(bytes.slice(cut));
        c.close();
      },
    });
    expect(await collect(stream)).toEqual([{ event: "delta", data: '{"text":"é"}' }]);
  });

  it("yields events across chunks", async () => {
    const got = await collect(streamOf("event: a\nda", "ta: 1\n\nevent: b\ndata: 2\n", "\n"));
    expect(got.map((m) => m.event)).toEqual(["a", "b"]);
  });
});

describe("parseChatEvent", () => {
  it("validates payloads and ignores unknown events", () => {
    expect(parseChatEvent("delta", '{"text":"x"}')).toEqual({ type: "delta", data: { text: "x" } });
    expect(parseChatEvent("delta", "{}")).toBeNull();
    expect(parseChatEvent("future", "{}")).toBeNull();
    expect(parseChatEvent("delta", "not json")).toBeNull();
  });
});
