import { UpstreamError } from "../providers.js";

type Opts = { signal: AbortSignal; firstByteMs: number; idleMs: number; onResponse?: (res: Response) => void };

function retryAfter(res: Response): number | undefined {
  const raw = res.headers.get("retry-after");
  const seconds = raw ? Number(raw) : NaN;
  return Number.isFinite(seconds) ? Math.min(seconds, 3600) * 1000 : undefined;
}

function errorText(body: string): string {
  try {
    const parsed = JSON.parse(body);
    const msg = parsed?.error?.message ?? parsed?.error ?? parsed?.message;
    if (typeof msg === "string") return msg;
  } catch {
    /* not JSON */
  }
  return body;
}

/**
 * POSTs JSON and yields response lines. A timer covers the wait for the first
 * bytes (firstByteMs) and then each gap between chunks (idleMs). Caller abort
 * propagates; timeouts surface as retryable UpstreamError(0).
 */
export async function* postLines(url: string, headers: Record<string, string>, body: unknown, opts: Opts): AsyncGenerator<string> {
  const ctl = new AbortController();
  let timedOut = false;
  let timer: NodeJS.Timeout | undefined;
  const arm = (ms: number) => {
    clearTimeout(timer);
    timer = setTimeout(() => {
      timedOut = true;
      ctl.abort();
    }, ms);
  };
  const onAbort = () => ctl.abort();
  if (opts.signal.aborted) ctl.abort();
  opts.signal.addEventListener("abort", onAbort, { once: true });
  arm(opts.firstByteMs);

  try {
    let res: Response;
    try {
      res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json", ...headers },
        body: JSON.stringify(body),
        signal: ctl.signal,
      });
    } catch (e) {
      if (timedOut) throw new UpstreamError(0, "timeout waiting for response");
      if (opts.signal.aborted) throw e;
      throw new UpstreamError(0, `network error: ${(e as Error).message}`);
    }
    opts.onResponse?.(res);
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new UpstreamError(res.status, errorText(text) || `HTTP ${res.status}`, retryAfter(res));
    }
    if (!res.body) throw new UpstreamError(0, "empty response body");

    const decoder = new TextDecoder();
    let buffer = "";
    try {
      for await (const chunk of res.body as unknown as AsyncIterable<Uint8Array>) {
        arm(opts.idleMs);
        buffer += decoder.decode(chunk, { stream: true });
        let nl: number;
        while ((nl = buffer.indexOf("\n")) >= 0) {
          const line = buffer.slice(0, nl).replace(/\r$/, "");
          buffer = buffer.slice(nl + 1);
          yield line;
        }
      }
    } catch (e) {
      if (timedOut) throw new UpstreamError(0, "stream stalled");
      if (opts.signal.aborted) throw e;
      if (e instanceof UpstreamError) throw e;
      throw new UpstreamError(0, `stream error: ${(e as Error).message}`);
    }
    buffer += decoder.decode();
    if (buffer.trim()) yield buffer;
  } finally {
    clearTimeout(timer);
    opts.signal.removeEventListener("abort", onAbort);
    ctl.abort();
  }
}
