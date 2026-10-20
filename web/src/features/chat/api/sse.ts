export interface SseMessage {
  event: string;
  data: string;
}

const LINE_BREAK = /\r\n|\n|\r(?!$)/;

export class SseParser {
  private buffer = "";
  private event = "";
  private data: string[] = [];

  push(chunk: string): SseMessage[] {
    this.buffer += chunk;
    const out: SseMessage[] = [];
    for (let match = LINE_BREAK.exec(this.buffer); match; match = LINE_BREAK.exec(this.buffer)) {
      const line = this.buffer.slice(0, match.index);
      this.buffer = this.buffer.slice(match.index + match[0].length);
      const message = this.line(line);
      if (message) out.push(message);
    }
    return out;
  }

  flush(): SseMessage[] {
    const out = this.push("\n");
    const tail = this.line("");
    if (tail) out.push(tail);
    return out;
  }

  private line(line: string): SseMessage | null {
    if (line === "") return this.dispatch();
    if (line.startsWith(":")) return null;
    const colon = line.indexOf(":");
    const field = colon === -1 ? line : line.slice(0, colon);
    let value = colon === -1 ? "" : line.slice(colon + 1);
    if (value.startsWith(" ")) value = value.slice(1);
    if (field === "event") this.event = value;
    else if (field === "data") this.data.push(value);
    return null;
  }

  private dispatch(): SseMessage | null {
    const hadData = this.data.length > 0;
    const message = { event: this.event || "message", data: this.data.join("\n") };
    this.event = "";
    this.data = [];
    return hadData ? message : null;
  }
}

export async function* readSse(stream: ReadableStream<Uint8Array>): AsyncGenerator<SseMessage> {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  const parser = new SseParser();
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      yield* parser.push(decoder.decode(value, { stream: true }));
    }
    yield* parser.push(decoder.decode());
    yield* parser.flush();
  } finally {
    reader.releaseLock();
  }
}
