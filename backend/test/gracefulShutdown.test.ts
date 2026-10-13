import { test } from "node:test";
import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import express from "express";
import { openSse } from "../src/util/sse.js";
import { activeStreams, drainGuard, gracefulShutdown, isDraining, resetLifecycleForTests } from "../src/util/lifecycle.js";
import { healthRouter } from "../src/routes/health.js";

function makeApp(release: Promise<void>) {
  const app = express();
  app.use(drainGuard());
  app.use("/health", healthRouter);
  app.get("/stream", async (_req, res) => {
    const sse = openSse(res);
    sse.send("delta", { text: "first" });
    await release;
    sse.send("delta", { text: "second" });
    sse.send("done", {});
    sse.end();
  });
  app.get("/ping", (_req, res) => void res.json({ ok: true }));
  return app;
}

test("graceful shutdown: drains an in-flight SSE stream, refuses new work, health 503, then exits", async () => {
  resetLifecycleForTests();
  let releaseStream!: () => void;
  const release = new Promise<void>((r) => (releaseStream = r));
  const server = makeApp(release).listen(0);
  await new Promise((r) => server.once("listening", r));
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;

  const streamRes = await fetch(`${base}/stream`);
  const reader = streamRes.body!.getReader();
  const first = new TextDecoder().decode((await reader.read()).value);
  assert.match(first, /first/);
  assert.equal(activeStreams(), 1);

  let exited: number | null = null;
  let cleaned = false;
  const done = gracefulShutdown(server, {
    graceMs: 5_000,
    cleanup: async () => void (cleaned = true),
    exit: (c) => void (exited = c),
  });
  assert.equal(isDraining(), true);

  // The stream is still open; the process has not exited.
  await new Promise((r) => setTimeout(r, 50));
  assert.equal(exited, null);

  // Let the answer finish: the client reads the rest, then the process exits cleanly.
  releaseStream();
  let rest = "";
  for (;;) {
    const { value, done: end } = await reader.read();
    if (end) break;
    rest += new TextDecoder().decode(value);
  }
  assert.match(rest, /second/);
  assert.match(rest, /event: done/);
  await done;
  assert.equal(exited, 0);
  assert.equal(cleaned, true);
  resetLifecycleForTests();
});

test("graceful shutdown: drain guard answers 503 with Connection: close, health reports draining", async () => {
  resetLifecycleForTests();
  let releaseStream!: () => void;
  const release = new Promise<void>((r) => (releaseStream = r));
  // A second listener on the same app plays the role of a keep-alive socket that is still connected.
  const app = makeApp(release);
  const server = app.listen(0);
  const probe = app.listen(0);
  await Promise.all([new Promise((r) => server.once("listening", r)), new Promise((r) => probe.once("listening", r))]);
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const probeBase = `http://127.0.0.1:${(probe.address() as AddressInfo).port}`;

  const streamRes = await fetch(`${base}/stream`);
  const reader = streamRes.body!.getReader();
  await reader.read();

  let exited = false;
  const done = gracefulShutdown(server, { graceMs: 5_000, cleanup: async () => {}, exit: () => void (exited = true) });

  const health = await fetch(`${probeBase}/health`);
  assert.equal(health.status, 503);
  assert.equal(((await health.json()) as { status: string }).status, "draining");
  assert.equal(health.headers.get("connection"), "close");

  const ping = await fetch(`${probeBase}/ping`);
  assert.equal(ping.status, 503);
  assert.equal(ping.headers.get("connection"), "close");
  assert.equal(((await ping.json()) as { error: { code: string } }).error.code, "restarting");

  releaseStream();
  while (!(await reader.read()).done) {
    /* drain */
  }
  await done;
  assert.equal(exited, true);
  probe.close();
  resetLifecycleForTests();
});

test("graceful shutdown: a stream past the grace period is cut and the process still exits", async () => {
  resetLifecycleForTests();
  const never = new Promise<void>(() => {});
  const server = makeApp(never).listen(0);
  await new Promise((r) => server.once("listening", r));
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const streamRes = await fetch(`${base}/stream`);
  const reader = streamRes.body!.getReader();
  await reader.read();

  let exited = false;
  const started = Date.now();
  await gracefulShutdown(server, { graceMs: 150, cleanup: async () => {}, exit: () => void (exited = true) });
  assert.equal(exited, true);
  assert.ok(Date.now() - started >= 140);
  await reader.read().catch(() => undefined); // socket was closed
  resetLifecycleForTests();
});
