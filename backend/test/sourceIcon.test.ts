import assert from "node:assert/strict";
import { test } from "node:test";
import { githubAvatarUrl, pickIconUrl, resolveIconUrl } from "../src/ingest/icon.js";

const base = "https://example.com/docs/guide/";

test("rel=icon resolves a relative href against the page", () => {
  assert.equal(pickIconUrl(`<head><link rel="icon" href="/static/f.png"></head>`, base), "https://example.com/static/f.png");
  assert.equal(pickIconUrl(`<link rel='shortcut icon' href='f.png'>`, base), "https://example.com/docs/guide/f.png");
  assert.equal(pickIconUrl(`<link href="//cdn.example.org/i.png" rel="icon">`, base), "https://cdn.example.org/i.png");
});

test("apple-touch-icon beats rel=icon, and the largest size wins", () => {
  const html = `<link rel="icon" href="/a.png"><link rel="apple-touch-icon" sizes="57x57" href="/s.png"><link rel="apple-touch-icon" sizes="180x180" href="/b.png">`;
  assert.equal(pickIconUrl(html, base), "https://example.com/b.png");
});

test("svg icons are skipped in favour of bitmaps", () => {
  const html = `<link rel="icon" type="image/svg+xml" href="/i.svg"><link rel="icon" sizes="32x32" href="/i32.png">`;
  assert.equal(pickIconUrl(html, base), "https://example.com/i32.png");
});

test("og:image is the fallback, then /favicon.ico", () => {
  assert.equal(pickIconUrl(`<meta property="og:image" content="/og.jpg">`, base), "https://example.com/og.jpg");
  assert.equal(pickIconUrl(`<html><body>nothing</body></html>`, base), "https://example.com/favicon.ico");
});

test("http icons are upgraded to https and data: URLs ignored", () => {
  assert.equal(pickIconUrl(`<link rel="icon" href="http://example.com/x.png">`, base), "https://example.com/x.png");
  assert.equal(pickIconUrl(`<link rel="icon" href="data:image/png;base64,AAAA">`, base), "https://example.com/favicon.ico");
});

test("github sources use the owner avatar", async () => {
  assert.equal(githubAvatarUrl("vercel"), "https://github.com/vercel.png?size=96");
  assert.equal(await resolveIconUrl("github", "vercel/next.js/tree/main"), "https://github.com/vercel.png?size=96");
  assert.equal(await resolveIconUrl("note", "note:abc"), null);
});
