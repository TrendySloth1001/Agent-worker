import type { Server } from "node:http";
import type { NextFunction, Request, Response } from "express";

/**
 * Graceful shutdown. On SIGTERM (a redeploy) the server:
 *  1. starts draining: /health answers 503 so the proxy stops routing here, new requests get a
 *     friendly 503 with `Connection: close`, and the listener stops accepting connections;
 *  2. lets in-flight streams (SSE answers) finish, up to `graceMs`;
 *  3. closes the remaining keep-alive sockets and exits.
 * The client retries a dropped stream once or twice, so a stream cut at the deadline still recovers.
 */

let draining = false;
const streams = new Set<Response>();
const waiters = new Set<() => void>();

export function isDraining(): boolean {
  return draining;
}

export function activeStreams(): number {
  return streams.size;
}

/** Counts a long-lived response (SSE) until it closes, so shutdown waits for it. */
export function trackStream(res: Response): void {
  streams.add(res);
  res.on("close", () => {
    streams.delete(res);
    if (streams.size === 0) for (const w of [...waiters]) w();
  });
}

/** Resolves when no tracked stream is open, or after `ms` (true = drained cleanly). */
export function waitForStreams(ms: number): Promise<boolean> {
  if (streams.size === 0) return Promise.resolve(true);
  return new Promise((resolve) => {
    const done = (ok: boolean) => {
      clearTimeout(timer);
      waiters.delete(onEmpty);
      resolve(ok);
    };
    const onEmpty = () => done(true);
    const timer = setTimeout(() => done(false), ms);
    timer.unref?.();
    waiters.add(onEmpty);
  });
}

/** While draining: refuse new work (except /health, which reports 503 itself) and close each socket after its response. */
export function drainGuard() {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!draining) return next();
    res.setHeader("Connection", "close");
    if (req.path === "/health" || req.path.startsWith("/health/")) return next();
    res.setHeader("Retry-After", "5");
    res.status(503).json({ error: { code: "restarting", message: "sparky is restarting — try again in a few seconds." } });
  };
}

export type ShutdownOptions = {
  graceMs: number;
  /** Final cleanup (flush telemetry, close the DB) after streams finished. */
  cleanup: () => Promise<void>;
  exit: (code: number) => void;
  log?: (msg: string, meta?: Record<string, unknown>) => void;
};

/** Runs the drain sequence once; later calls return the same promise. */
let running: Promise<void> | null = null;
export function gracefulShutdown(server: Server, opts: ShutdownOptions): Promise<void> {
  if (running) return running;
  running = (async () => {
    draining = true;
    opts.log?.("shutdown: draining", { streams: streams.size, graceMs: opts.graceMs });
    // Stop accepting new connections; idle keep-alive sockets are closed now, busy ones after their response.
    server.close();
    server.closeIdleConnections?.();
    // Sockets that finish a response later go idle too: keep closing them while streams drain.
    const sweep = setInterval(() => server.closeIdleConnections?.(), 1_000);
    sweep.unref?.();
    const clean = await waitForStreams(opts.graceMs);
    clearInterval(sweep);
    opts.log?.("shutdown: streams finished", { clean, left: streams.size });
    server.closeAllConnections?.();
    await opts.cleanup().catch(() => undefined);
    opts.exit(0);
  })();
  return running;
}

/** Test hook: reset module state. */
export function resetLifecycleForTests(): void {
  draining = false;
  running = null;
  streams.clear();
  waiters.clear();
}
