import type { Response } from "express";

export type SseWriter = {
  send(event: string, data: unknown): void;
  end(): void;
  readonly open: boolean;
};

/** Starts an SSE response: headers flushed immediately, `: ping` every 15 s. */
export function openSse(res: Response): SseWriter {
  res.status(200);
  res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.setHeader("X-Accel-Buffering", "no");
  res.flushHeaders();
  res.socket?.setNoDelay(true);

  let open = true;
  res.on("close", () => {
    open = false;
    clearInterval(ping);
  });
  const ping = setInterval(() => {
    if (open) res.write(": ping\n\n");
  }, 15_000);

  return {
    send(event, data) {
      if (open) res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    },
    end() {
      clearInterval(ping);
      if (open) {
        open = false;
        res.end();
      }
    },
    get open() {
      return open;
    },
  };
}
