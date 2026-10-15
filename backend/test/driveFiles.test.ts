import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import express from "express";
import type { AddressInfo } from "node:net";
import { createDrive, previewExport, safeRange, GDOC, GSHEET, GSLIDES, GFOLDER, MAX_PROXY_BYTES, type DriveFile } from "../src/connections/oauth/drive.js";
import { sendDriveFile, proxyHeaders } from "../src/connections/oauth/driveProxy.js";
import { createDriveInsights, type InsightCache } from "../src/connections/oauth/driveInsight.js";
import { createPicker, pickerPage, pickedItem, MAX_IMPORT, type PickedItem } from "../src/connections/oauth/picker.js";
import type { FlowRow, FlowStore } from "../src/connections/oauth/flow.js";
import type { TokenManager } from "../src/connections/oauth/tokens.js";
import { AppError } from "../src/util/errors.js";

const TOKEN = "ya29.SECRET-GOOGLE-TOKEN";
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const isApp = (status: number, code: string) => (e: unknown) => e instanceof AppError && e.status === status && e.code === code;
const tokens = { accessToken: async () => TOKEN, rejected: async () => { throw new AppError(401, "connector_reauth", "reauth"); } } as unknown as TokenManager;

type Call = { url: string; init: RequestInit };
function mockFetch(handler: (url: string, init: RequestInit) => Response | Promise<Response>) {
  const calls: Call[] = [];
  const f = (async (input: string | URL | Request, init: RequestInit = {}) => {
    calls.push({ url: String(input), init });
    return handler(String(input), init);
  }) as typeof fetch;
  return { f, calls };
}

const META = (o: Record<string, unknown>) => ({ id: "file1234567890", name: "Plan.pdf", mimeType: "application/pdf", modifiedTime: "2026-10-01T10:00:00.000Z", size: "11", ...o });

// ---- the preview proxy ---------------------------------------------------------------

test("export mapping: native Google files become PDF, everything else is streamed as stored", () => {
  for (const m of [GDOC, GSHEET, GSLIDES, "application/vnd.google-apps.drawing"]) assert.equal(previewExport(m), "application/pdf");
  assert.equal(previewExport("application/pdf"), null);
  assert.equal(previewExport("image/png"), null);
  assert.equal(previewExport("application/vnd.openxmlformats-officedocument.wordprocessingml.document"), null);
});

test("safeRange keeps one well-formed byte range only", () => {
  assert.equal(safeRange("bytes=0-99"), "bytes=0-99");
  assert.equal(safeRange("bytes=100-"), "bytes=100-");
  assert.equal(safeRange("bytes=-500"), "bytes=-500");
  assert.equal(safeRange("bytes=0-1,5-9"), null);
  assert.equal(safeRange("bytes=-"), null);
  assert.equal(safeRange("items=0-1"), null);
  assert.equal(safeRange(undefined), null);
});

test("proxy: a Google Doc is exported to PDF; the Google token only goes to Google", async () => {
  const { f, calls } = mockFetch((url) => {
    if (url.includes("/export")) return new Response("%PDF-1.7", { headers: { "content-length": "8" } });
    return json(META({ id: "doc1234567890", name: "Plan", mimeType: GDOC }));
  });
  const s = await createDrive(tokens, f).stream("u1", "doc1234567890", "bytes=0-3");
  assert.equal(s.contentType, "application/pdf");
  assert.equal(s.status, 200);
  assert.match(calls[1].url, /\/files\/doc1234567890\/export\?mimeType=application%2Fpdf/);
  // Exports cannot be ranged: the range is not forwarded.
  assert.equal(new Headers(calls[1].init.headers).get("Range"), null);
  assert.equal(new Headers(calls[1].init.headers).get("Authorization"), `Bearer ${TOKEN}`);
  const h = proxyHeaders(s);
  assert.ok(!JSON.stringify(h).includes(TOKEN));
  assert.equal(h.ETag, '"2026-10-01T10:00:00.000Z"');
  assert.equal(h["X-Content-Type-Options"], "nosniff");
});

test("proxy: stored files stream as they are, a single range is passed on and 206 is kept", async () => {
  const { f, calls } = mockFetch((url, init) => {
    if (url.includes("alt=media")) {
      assert.equal(new Headers(init.headers).get("Range"), "bytes=2-5");
      return new Response("cdef", { status: 206, headers: { "content-range": "bytes 2-5/11", "content-length": "4", "set-cookie": "g=1", authorization: "x" } });
    }
    return json(META({ mimeType: "video/mp4", name: "clip.mp4" }));
  });
  const s = await createDrive(tokens, f).stream("u1", "file1234567890", "bytes=2-5");
  assert.equal(s.status, 206);
  assert.equal(s.contentType, "video/mp4");
  assert.equal(s.headers["content-range"], "bytes 2-5/11");
  assert.equal(s.headers["set-cookie"], undefined);
  assert.equal(s.headers["accept-ranges"], "bytes");
  assert.equal(calls.length, 2);
  // A malformed range is dropped rather than forwarded.
  const g = mockFetch((url, init) => {
    if (url.includes("alt=media")) {
      assert.equal(new Headers(init.headers).get("Range"), null);
      return new Response("0123456789a");
    }
    return json(META({}));
  });
  assert.equal((await createDrive(tokens, g.f).stream("u1", "file1234567890", "bytes=0-1,3-4")).status, 200);
});

test("proxy: only files sparky can see (ownership), no folders, no huge files", async () => {
  const gone = mockFetch(() => json({ error: { message: "File not found" } }, 404));
  await assert.rejects(createDrive(tokens, gone.f).stream("u1", "other1234567890"), isApp(404, "not_found"));
  assert.equal(gone.calls.length, 1, "a file the token cannot see is never downloaded");
  await assert.rejects(createDrive(tokens, gone.f).stream("u1", "../../etc/passwd"), isApp(400, "bad_request"));
  const folder = mockFetch(() => json(META({ mimeType: GFOLDER })));
  await assert.rejects(createDrive(tokens, folder.f).stream("u1", "file1234567890"), isApp(422, "unprocessable"));
  const big = mockFetch(() => json(META({ size: String(MAX_PROXY_BYTES + 1) })));
  await assert.rejects(createDrive(tokens, big.f).stream("u1", "file1234567890"), isApp(413, "too_large"));
  const exportTooBig = mockFetch((url) => (url.includes("/export") ? json({ error: {} }, 403) : json(META({ mimeType: GSHEET }))));
  await assert.rejects(createDrive(tokens, exportTooBig.f).stream("u1", "file1234567890"), isApp(413, "too_large"));
});

test("proxy over HTTP: streams the body, forwards range headers, answers 304 on a matching ETag", async () => {
  const upstream = mockFetch((url) => {
    if (url.includes("alt=media")) return new Response("cdef", { status: 206, headers: { "content-range": "bytes 2-5/11", "content-length": "4" } });
    return json(META({ mimeType: "image/png", name: "a b.png" }));
  });
  const d = createDrive(tokens, upstream.f);
  const app = express();
  app.get("/raw", async (req, res) => {
    await sendDriveFile(res, await d.stream("u1", "file1234567890", req.header("range")), req.header("if-none-match"));
  });
  const server = app.listen(0);
  try {
    const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}/raw`;
    const r = await fetch(base, { headers: { Range: "bytes=2-5" } });
    assert.equal(r.status, 206);
    assert.equal(await r.text(), "cdef");
    assert.equal(r.headers.get("content-range"), "bytes 2-5/11");
    assert.equal(r.headers.get("content-type"), "image/png");
    assert.match(r.headers.get("content-disposition")!, /a%20b\.png/);
    assert.ok(![...r.headers.values()].some((v) => v.includes(TOKEN)));
    const plain = mockFetch((url) => (url.includes("alt=media") ? new Response("hello") : json(META({ mimeType: "image/png" }))));
    const d2 = createDrive(tokens, plain.f);
    const app2 = express();
    app2.get("/raw", async (req, res) => sendDriveFile(res, await d2.stream("u1", "file1234567890"), req.header("if-none-match")));
    const s2 = app2.listen(0);
    try {
      const b2 = `http://127.0.0.1:${(s2.address() as AddressInfo).port}/raw`;
      const full = await fetch(b2);
      assert.equal(await full.text(), "hello");
      const etag = full.headers.get("etag")!;
      const again = await fetch(b2, { headers: { "If-None-Match": etag } });
      assert.equal(again.status, 304);
    } finally {
      s2.close();
    }
  } finally {
    server.close();
  }
});

// ---- insight -------------------------------------------------------------------------------

function insightKit(initial: Partial<DriveFile> = {}) {
  const file: DriveFile = { id: "doc1234567890", name: "Plan", mimeType: GDOC, modifiedTime: "v1", size: null, iconLink: null, webViewLink: null, thumbnailLink: null, owner: null, kind: "markdown", ...initial };
  const store = new Map<string, { modifiedTime: string; sealed: string }>();
  const cache: InsightCache = {
    async get(u, f) {
      return store.get(`${u}:${f}`) ?? null;
    },
    async put(u, f, modifiedTime, sealed) {
      store.set(`${u}:${f}`, { modifiedTime, sealed });
    },
  };
  const state = { chat: 0, vision: 0, reads: 0, text: "Quarterly plan: ship the picker by Friday." };
  const svc = createDriveInsights({
    drive: {
      meta: async (_u: string, id: string) => {
        if (id !== file.id) throw new AppError(404, "not_found", "gone");
        return { ...file };
      },
      read: async () => {
        state.reads++;
        return { file, format: "markdown" as const, text: state.text, truncated: false };
      },
      stream: async () => ({ file, status: 200, contentType: "image/png", headers: {}, body: new Response("png-bytes").body }),
    },
    cache,
    ai: {
      chat: async () => {
        state.chat++;
        await new Promise((r) => setTimeout(r, 5));
        return JSON.stringify({ summary: "A plan to ship.", keyPoints: ["Friday"] });
      },
      vision: async () => {
        state.vision++;
        return JSON.stringify({ caption: "A cat", text: "MEOW", keyPoints: ["cat"] });
      },
      now: () => new Date("2026-10-01T00:00:00Z"),
    },
    crypto: async (u) => ({ seal: (_t, _c, v) => `sealed:${u}:${Buffer.from(v).toString("base64")}`, open: (_t, _c, v) => Buffer.from(v.split(":")[2], "base64").toString() }),
    jpeg: async (b) => b.toString("base64"),
  });
  return { svc, file, store, state };
}

test("drive insight: generated once per modifiedTime, sealed in the cache, regenerated when the file changes", async () => {
  const { svc, file, store, state } = insightKit();
  assert.equal((await svc.get("u1", "doc1234567890")).insight, null);
  const [a, b] = await Promise.all([svc.ensure("u1", "doc1234567890"), svc.ensure("u1", "doc1234567890")]);
  assert.equal(a.insight?.summary, "A plan to ship.");
  assert.deepEqual(b.insight?.keyPoints, ["Friday"]);
  assert.equal(state.chat, 1, "concurrent calls share one generation");
  const stored = store.get("u1:doc1234567890")!;
  assert.equal(stored.modifiedTime, "v1");
  assert.ok(!stored.sealed.includes("A plan to ship"), "the cache holds ciphertext, not the summary");
  await svc.ensure("u1", "doc1234567890");
  assert.equal(state.chat, 1, "same modifiedTime is a cache hit");
  assert.equal((await svc.get("u1", "doc1234567890")).insight?.summary, "A plan to ship.");
  file.modifiedTime = "v2";
  assert.equal((await svc.get("u1", "doc1234567890")).insight, null, "an edited file misses the cache");
  await svc.ensure("u1", "doc1234567890");
  assert.equal(state.chat, 2);
  assert.equal(store.get("u1:doc1234567890")!.modifiedTime, "v2");
  await svc.ensure("u1", "doc1234567890", { force: true });
  assert.equal(state.chat, 3);
  // Another user never sees it (and cannot reach files they do not own).
  assert.equal((await svc.get("u2", "doc1234567890")).insight, null);
  await assert.rejects(svc.ensure("u1", "other1234567890"), isApp(404, "not_found"));
});

test("drive insight: images use vision; files with nothing to read say so", async () => {
  const img = insightKit({ id: "img1234567890", name: "cat.png", mimeType: "image/png", kind: "none", size: 9 });
  const p = await img.svc.ensure("u1", "img1234567890");
  assert.equal(p.kind, "image");
  assert.equal(p.insight?.ocr, "MEOW");
  assert.equal(img.state.vision, 1);
  assert.equal(img.state.chat, 0);
  const empty = insightKit();
  empty.state.text = "   ";
  await assert.rejects(empty.svc.ensure("u1", "doc1234567890"), isApp(404, "not_found"));
});

test("drive text is paged", async () => {
  const { svc, state } = insightKit();
  state.text = "x".repeat(50);
  const t = await svc.text("u1", "doc1234567890", 10, 20);
  assert.equal(t.text.length, 20);
  assert.equal(t.offset, 10);
  assert.equal(t.truncated, true);
  assert.equal(t.chars, 50);
});

// ---- folders and the picker ------------------------------------------------------------------

function memoryFlows(): FlowStore & { rows: FlowRow[] } {
  const rows: FlowRow[] = [];
  const find = (provider: string, mode: string, h: string, now: Date) => rows.find((x) => x.stateHash === h && x.provider === provider && x.mode === mode && x.status === "pending" && x.expiresAt > now);
  return {
    rows,
    async create(r) {
      rows.push({ ...r, id: randomUUID(), status: "pending", ticketHash: null, ticketExpiresAt: null, result: null });
    },
    async claim(provider, mode, h, now) {
      const r = find(provider, mode, h, now);
      if (!r) return null;
      r.status = "exchanging";
      return { ...r };
    },
    async peek(provider, mode, h, now) {
      const r = find(provider, mode, h, now);
      return r ? { ...r } : null;
    },
    async ready() {},
    async fail() {},
    async consume() {
      return null;
    },
    async hasConnection() {
      return true;
    },
    async purge() {},
  } as unknown as FlowStore & { rows: FlowRow[] };
}

const item = (id: string, name = id, o: Partial<PickedItem> = {}): PickedItem => ({ id, name, folder: false, supported: true, ...o });
const FOLDER_ID = "folder1234567890";

function pickerKit(listing: (folderId: string) => { ok: boolean; status: number; items: PickedItem[] }, known: Record<string, PickedItem>) {
  const listed: string[] = [];
  const p = createPicker({
    store: memoryFlows(),
    tokens: { accessToken: async () => "at" } as unknown as TokenManager,
    now: Date.now,
    apiKey: () => "AIza",
    clientId: () => "123456789012-abc.apps.googleusercontent.com",
    baseUrl: () => "https://sparky.example",
    inspect: async (_u, id) => known[id] ?? null,
    children: async (_u, id) => {
      listed.push(id);
      return listing(id);
    },
  });
  return { p, listed };
}

const ticketOf = async (p: ReturnType<typeof createPicker>) => new URL((await p.start("u1")).url).searchParams.get("ticket")!;

test("pickedItem: folders apart; unsupported types are not importable", () => {
  assert.equal(pickedItem({ id: "a", name: "F", mimeType: GFOLDER, kind: "none" }).folder, true);
  assert.equal(pickedItem({ id: "a", name: "x.zip", mimeType: "application/zip", kind: "none" }).supported, false);
  assert.equal(pickedItem({ id: "a", name: "x.png", mimeType: "image/png", kind: "none" }).supported, true);
  assert.equal(pickedItem({ id: "a", name: "x.pdf", mimeType: "application/pdf", kind: "pdf" }).supported, true);
});

test("folder with listable children: files are imported, capped, unsupported skipped", async () => {
  const kids = [
    ...Array.from({ length: MAX_IMPORT + 7 }, (_, i) => item(`child${String(i).padStart(10, "0")}`)),
    item("zipfile1234567", "a.zip", { supported: false }),
    item("subfolder123456", "sub", { folder: true }),
  ];
  const { p, listed } = pickerKit(() => ({ ok: true, status: 200, items: kids }), {
    [FOLDER_ID]: item(FOLDER_ID, "Reports", { folder: true }),
    file1234567890: item("file1234567890"),
  });
  const t = await ticketOf(p);
  const r = await p.done(t, [FOLDER_ID, "file1234567890", "nothere1234567"]);
  assert.deepEqual(listed, [FOLDER_ID]);
  assert.equal(r.picked, 1, "the plain pick; unknown ids are dropped");
  assert.equal(r.imported, MAX_IMPORT);
  assert.equal(r.skipped, 7 + 1, "over the cap and unsupported");
  assert.equal(r.folders, 1);
  assert.deepEqual(r.fallback, []);
  const link = new URL(r.link);
  assert.equal(link.searchParams.get("imported"), String(MAX_IMPORT));
  assert.equal(link.searchParams.get("limited"), null);
});

test("folder denied or empty (expected under drive.file): fallback list, resolve keeps the ticket, handled folders are not listed again", async () => {
  const known = {
    [FOLDER_ID]: item(FOLDER_ID, "Reports", { folder: true }),
    folder2234567890: item("folder2234567890", "Receipts", { folder: true }),
    file1234567890: item("file1234567890"),
  };
  const { p, listed } = pickerKit((id) => (id === FOLDER_ID ? { ok: false, status: 404, items: [] } : { ok: true, status: 200, items: [] }), known);
  const t = await ticketOf(p);
  const r = await p.resolve(t, [FOLDER_ID, "folder2234567890", "file1234567890"]);
  assert.deepEqual(r.fallback, [{ id: FOLDER_ID, name: "Reports" }, { id: "folder2234567890", name: "Receipts" }], "folders are handled in order");
  assert.equal(r.imported, 0);
  // The ticket is still valid after resolve; done consumes it.
  const done = await p.done(t, [FOLDER_ID, "folder2234567890", "file1234567890", "inside1234567"], [FOLDER_ID]);
  assert.deepEqual(done.fallback.map((f) => f.id), ["folder2234567890"], "a folder whose files were picked inside is not reported");
  assert.equal(done.picked, 1);
  assert.equal(new URL(done.link).searchParams.get("limited"), "1");
  assert.equal(new URL(done.link).searchParams.get("folders"), "2");
  assert.deepEqual(listed.filter((x) => x === FOLDER_ID).length, 1, "only resolve listed the handled folder");
  await assert.rejects(p.done(t, []), (e: unknown) => e instanceof AppError && e.code === "invalid_ticket");
  await assert.rejects(p.resolve(t, []), (e: unknown) => e instanceof AppError && e.code === "invalid_ticket");
});

test("folder listing that throws counts as denied", async () => {
  const { p } = pickerKit(() => {
    throw new Error("boom");
  }, { [FOLDER_ID]: item(FOLDER_ID, "Reports", { folder: true }) });
  const r = await p.resolve(await ticketOf(p), [FOLDER_ID]);
  assert.equal(r.fallback.length, 1);
});

test("drive.children asks for the folder's non-trashed children and reports denial", async () => {
  const ok = mockFetch(() => json({ files: [{ id: "c1", name: "a.pdf", mimeType: "application/pdf" }] }));
  const r = await createDrive(tokens, ok.f).children("u1", FOLDER_ID);
  assert.equal(r.ok, true);
  assert.equal(r.files[0].kind, "pdf");
  const q = new URL(ok.calls[0].url).searchParams.get("q")!;
  assert.equal(q, `'${FOLDER_ID}' in parents and trashed = false`);
  const denied = mockFetch(() => json({ error: {} }, 403));
  const d = await createDrive(tokens, denied.f).children("u1", FOLDER_ID);
  assert.deepEqual([d.ok, d.status, d.files.length], [false, 403, 0]);
});

test("picker page: folders are selectable, multiselect stays on, folder fallback reopens the picker inside the folder", async () => {
  const { p } = pickerKit(() => ({ ok: true, status: 200, items: [] }), {});
  const t = await ticketOf(p);
  const html = pickerPage(await p.view(t), "n0nce");
  assert.match(html, /setSelectFolderEnabled\(true\)/);
  assert.ok(!html.includes("setSelectFolderEnabled(false)"));
  assert.match(html, /MULTISELECT_ENABLED/);
  assert.match(html, /setParent\(f\.id\)/);
  assert.match(html, /"Pick files in "\+f\.name/);
  assert.match(html, /\/resolve/);
  assert.match(html, /"base":"https:\/\/sparky\.example\/connect\/google_drive\/picker"/);
  assert.ok(!html.includes(TOKEN));
});
