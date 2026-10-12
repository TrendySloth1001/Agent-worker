import { test } from "node:test";
import assert from "node:assert/strict";
import express from "express";
import type { AddressInfo } from "node:net";
import { isAudio, languageHint, MAX_VOICE_BYTES, transcribeRouter } from "../src/assist/transcribe.js";
import { errorMiddleware } from "../src/util/errors.js";

type Post = (init?: RequestInit) => Promise<Response>;

async function withServer(fn: (post: Post) => Promise<void>) {
  const app = express();
  app.use("/assist", transcribeRouter);
  app.use(errorMiddleware);
  const server = app.listen(0);
  const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}/assist/transcribe`;
  try {
    await fn((init) => fetch(url, { method: "POST", ...init }));
  } finally {
    server.closeAllConnections();
    server.close();
  }
}

const clip = (bytes: number, type: string, name: string) => {
  const f = new FormData();
  f.append("file", new Blob([new Uint8Array(bytes).fill(1)], { type }), name);
  return f;
};
const code = async (r: Response) => ((await r.json()) as { error: { code: string } }).error.code;

test("transcribe: a body that is not multipart is a 400", () =>
  withServer(async (post) => {
    const res = await post({ headers: { "content-type": "application/json" }, body: "{}" });
    assert.equal(res.status, 400);
    assert.equal(await code(res), "bad_request");
  }));

test("transcribe: no file field is a 400", () =>
  withServer(async (post) => {
    const f = new FormData();
    f.append("language", "en-IN");
    const res = await post({ body: f });
    assert.equal(res.status, 400);
    assert.equal(await code(res), "bad_request");
  }));

test("transcribe: a recording over the limit is a 413", () =>
  withServer(async (post) => {
    const res = await post({ body: clip(MAX_VOICE_BYTES + 1024, "audio/mp4", "voice.m4a") });
    assert.equal(res.status, 413);
    assert.equal(await code(res), "payload_too_large");
  }));

test("transcribe: a non-audio file is a 415", () =>
  withServer(async (post) => {
    const res = await post({ body: clip(100, "image/png", "pic.png") });
    assert.equal(res.status, 415);
    assert.equal(await code(res), "unsupported_media_type");
  }));

test("isAudio and languageHint", () => {
  assert.ok(isAudio("audio/mp4", "x"));
  assert.ok(isAudio("application/octet-stream", "v.m4a"));
  assert.ok(!isAudio("application/pdf", "v.pdf"));
  assert.equal(languageHint("en-IN"), "en");
  assert.equal(languageHint("hi_IN"), "hi");
  assert.equal(languageHint("nonsense!!"), undefined);
  assert.equal(languageHint(5), undefined);
});
