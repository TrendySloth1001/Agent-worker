import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { join } from "node:path";
import express from "express";
import type { AddressInfo } from "node:net";
import { siteRouter } from "../src/routes/site.js";

const hasSite = existsSync(join(process.cwd(), "site-public", "index.html"));

test("landing site is served at / with its assets and a strict CSP; legal pages still work", { skip: !hasSite }, async () => {
  const app = express();
  app.use(siteRouter);
  const server = app.listen(0);
  try {
    const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
    const home = await fetch(`${base}/`);
    assert.equal(home.status, 200);
    assert.match(home.headers.get("content-type") ?? "", /text\/html/);
    const csp = home.headers.get("content-security-policy") ?? "";
    assert.match(csp, /script-src 'self'/);
    assert.doesNotMatch(csp, /script-src[^;]*unsafe-inline/);
    const html = await home.text();
    assert.match(html, /sparky/);
    assert.doesNotMatch(html, /<script>(?!<\/script>)/, "no inline scripts (CSP would block them)");
    for (const [path, type] of [
      ["/css/style.css", /text\/css/],
      ["/js/dotmatrix.js", /javascript/],
      ["/js/theme-init.js", /javascript/],
      ["/assets/og.png", /image\/png/],
    ] as const) {
      const r = await fetch(`${base}${path}`);
      assert.equal(r.status, 200, path);
      assert.match(r.headers.get("content-type") ?? "", type, path);
      assert.match(r.headers.get("cache-control") ?? "", /public/, path);
    }
    assert.equal((await fetch(`${base}/privacy`)).status, 200);
    assert.equal((await fetch(`${base}/css/missing.css`)).status, 404);
  } finally {
    server.close();
  }
});
