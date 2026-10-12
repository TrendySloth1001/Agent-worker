import { randomBytes } from "node:crypto";
import { Router, type Request, type Response } from "express";
import { z } from "zod";
import { userOf } from "../auth/context.js";
import { callbackPage } from "../auth/githubWebPage.js";
import { drive, GDOC } from "../connections/oauth/drive.js";
import { connectRedirectUri, oauthFlow } from "../connections/oauth/flow.js";
import { notionApi } from "../connections/oauth/notion.js";
import { picker, pickerCsp, pickerPage } from "../connections/oauth/picker.js";
import { isProviderId, PROVIDER_IDS, PROVIDERS, providerConfigured, type ProviderId } from "../connections/oauth/providers.js";
import { connectorTokens } from "../connections/oauth/tokens.js";
import { listConnections } from "../connections/store.js";
import { db, type Prisma } from "../db/prisma.js";
import { prismaStore as docStore, isUuid } from "../docs/store.js";
import { toDocx, toMarkdown, fileName } from "../docs/export.js";
import { enqueue } from "../ingest/queue.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { rateLimit } from "../util/rateLimit.js";
import { config } from "../config.js";

/**
 * Google Drive and Notion (src/connections/oauth). The callback and the
 * picker page are public (the browser has no sparky session; state and
 * tickets authenticate them); everything else needs the signed-in user and
 * only ever touches that user's connection.
 */

/** For GET /connections: which connectors this server can offer. */
export function connectorProviders(): Record<ProviderId, { configured: boolean; web: boolean; picker?: boolean; redirectUri: string }> {
  const out = {} as Record<ProviderId, { configured: boolean; web: boolean; picker?: boolean; redirectUri: string }>;
  for (const id of PROVIDER_IDS) {
    const ok = providerConfigured(PROVIDERS[id]);
    out[id] = { configured: ok, web: ok, redirectUri: connectRedirectUri(id), ...(id === "google_drive" ? { picker: ok && !!config.googlePickerApiKey } : {}) };
  }
  return out;
}

const providerOf = (req: Request): ProviderId => {
  const p = String(req.params.provider);
  if (!isProviderId(p)) throw new AppError(404, "not_found", "Unknown app");
  return p;
};

const uid = (req: Request) => {
  const id = userOf(req).id;
  if (!id) throw new AppError(403, "forbidden", "Sign in with an account to connect apps");
  return id;
};

const noStore = (res: Response) => res.setHeader("Cache-Control", "no-store");
const q = (req: Request, k: string, max = 500) => (typeof req.query[k] === "string" ? (req.query[k] as string).slice(0, max) : undefined);

// ---- public: OAuth callback and the Drive picker page ------------------------

export const connectPublicRouter = Router();

connectPublicRouter.get("/:provider/callback", rateLimit(30, 60_000, "ip"));
connectPublicRouter.get("/google_drive/picker", rateLimit(30, 60_000, "ip"));
connectPublicRouter.post("/google_drive/picker/done", rateLimit(30, 60_000, "ip"));

connectPublicRouter.get("/:provider/callback", async (req, res, next) => {
  const p = String(req.params.provider);
  if (!isProviderId(p)) return next();
  const cb = await oauthFlow.callback(p, { code: q(req, "code", 2000), state: q(req, "state"), error: q(req, "error", 100) });
  if (cb.ok) log.info("connector approved", { provider: p });
  const nonce = randomBytes(16).toString("base64");
  noStore(res);
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Content-Security-Policy", `default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}'; frame-ancestors 'none'; base-uri 'none'`);
  res.type("html").send(
    callbackPage(cb, nonce, { name: cb.providerName, mark: cb.providerName.toLowerCase(), stopped: `${cb.providerName} connection stopped` }),
  );
});

connectPublicRouter.get("/google_drive/picker", async (req, res) => {
  const view = await picker.view(q(req, "ticket", 200) ?? "");
  const nonce = randomBytes(16).toString("base64");
  noStore(res);
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Content-Security-Policy", pickerCsp(nonce));
  res.type("html").send(pickerPage(view, nonce));
});

const doneBody = z.object({ ticket: z.string().min(20).max(200), ids: z.array(z.string().max(200)).max(200).default([]) });

connectPublicRouter.post("/google_drive/picker/done", async (req, res) => {
  const b = doneBody.parse(req.body ?? {});
  noStore(res);
  res.json(await picker.done(b.ticket, b.ids));
});

// ---- signed in ----------------------------------------------------------------

export const connectRouter = Router();

connectRouter.use((_req, res, next) => {
  noStore(res);
  next();
});

connectRouter.post("/:provider/start", rateLimit(10, 60_000));
connectRouter.post("/:provider/redeem", rateLimit(30, 60_000));
connectRouter.delete("/:provider", rateLimit(10, 60_000));
connectRouter.post("/google_drive/picker", rateLimit(20, 60_000));
connectRouter.get("/google_drive/files", rateLimit(60, 60_000));
connectRouter.get("/google_drive/files/:id", rateLimit(30, 60_000));
connectRouter.get("/notion/search", rateLimit(60, 60_000));
connectRouter.get("/notion/pages/:id", rateLimit(30, 60_000));
connectRouter.post("/google_drive/files/:id/knowledge", rateLimit(10, 60_000));
connectRouter.post("/notion/pages/:id/knowledge", rateLimit(10, 60_000));
connectRouter.post("/google_drive/upload", rateLimit(10, 60_000));
connectRouter.post("/notion/pages", rateLimit(10, 60_000));

const connectionOf = async (userId: string, p: ProviderId) => (await listConnections(userId)).find((c) => c.provider === p) ?? null;

connectRouter.post("/:provider/start", async (req, res) => {
  res.json(await oauthFlow.start(providerOf(req), uid(req)));
});

const ticketBody = z.object({ ticket: z.string().min(20).max(200) });

connectRouter.post("/:provider/redeem", async (req, res) => {
  const p = providerOf(req);
  const parsed = ticketBody.safeParse(req.body ?? {});
  if (!parsed.success) throw new AppError(400, "invalid_ticket", "This connection expired or was already used. Start again.");
  const id = uid(req);
  await oauthFlow.redeem(p, parsed.data.ticket, id);
  res.json({ ok: true, provider: p, connection: await connectionOf(id, p) });
});

connectRouter.delete("/:provider", async (req, res) => {
  const p = providerOf(req);
  res.json(await connectorTokens.disconnect(uid(req), p));
});

// ---- Google Drive -------------------------------------------------------------

connectRouter.post("/google_drive/picker", async (req, res) => {
  res.json(await picker.start(uid(req)));
});

connectRouter.get("/google_drive/files", async (req, res) => {
  res.json(await drive.list(uid(req), { q: q(req, "q", 200), pageToken: q(req, "pageToken") }));
});

connectRouter.get("/google_drive/files/:id", async (req, res) => {
  res.json(await drive.read(uid(req), String(req.params.id)));
});

// ---- Notion ---------------------------------------------------------------------

connectRouter.get("/notion/search", async (req, res) => {
  const kind = q(req, "kind");
  res.json(await notionApi.search(uid(req), { q: q(req, "q", 200), cursor: q(req, "cursor", 200), kind: kind === "page" || kind === "database" ? kind : undefined }));
});

connectRouter.get("/notion/pages/:id", async (req, res) => {
  res.json(await notionApi.read(uid(req), String(req.params.id)));
});

// ---- knowledge base -------------------------------------------------------------

const json = (v: Record<string, unknown>) => JSON.parse(JSON.stringify(v)) as Prisma.InputJsonObject;

/** Adds (or re-indexes) one app item as a knowledge-base source. */
async function addToKnowledge(userId: string, type: "google_drive" | "notion", uri: string, title: string, url: string) {
  const existing = await db().source.findFirst({ where: { userId, type, uri }, select: { id: true } });
  const row = existing
    ? await db().source.update({ where: { id: existing.id }, data: { title, status: "queued", updatedAt: new Date() }, select: { id: true, type: true, uri: true, title: true, status: true } })
    : await db().source.create({ data: { type, uri, title, options: json({ url }), userId }, select: { id: true, type: true, uri: true, title: true, status: true } });
  enqueue(row.id);
  return { source: row, refreshed: !!existing };
}

connectRouter.post("/google_drive/files/:id/knowledge", async (req, res) => {
  const id = uid(req);
  const file = await drive.meta(id, String(req.params.id));
  if (file.kind === "none") throw new AppError(422, "unprocessable", "sparky cannot read this kind of file, so it cannot go into your knowledge base.");
  res.status(202).json(await addToKnowledge(id, "google_drive", `gdrive:${file.id}`, file.name, file.webViewLink ?? ""));
});

connectRouter.post("/notion/pages/:id/knowledge", async (req, res) => {
  const id = uid(req);
  const page = await notionApi.read(id, String(req.params.id), 2_000);
  res.status(202).json(await addToKnowledge(id, "notion", `notion:${page.id}`, page.title, page.url));
});

// ---- saving (explicit user actions only) ----------------------------------------

const saveBody = z.union([
  z.object({ docId: z.string().refine(isUuid, "must be a doc id") }),
  z.object({ title: z.string().trim().min(1).max(200), markdown: z.string().min(1).max(400_000) }),
]);

async function contentOf(userId: string, body: z.infer<typeof saveBody>) {
  if ("docId" in body) {
    const doc = await docStore.get(userId, body.docId);
    if (!doc) throw new AppError(404, "not_found", "Document not found");
    return { title: doc.title || "Untitled doc", markdown: toMarkdown(doc), doc };
  }
  return { title: body.title, markdown: body.markdown, doc: null };
}

connectRouter.post("/google_drive/upload", async (req, res) => {
  const id = uid(req);
  const c = await contentOf(id, saveBody.parse(req.body ?? {}));
  // Docs go up as .docx converted to a Google Doc; chat exports as Markdown files.
  const file = c.doc
    ? await drive.upload(id, {
        name: fileName(c.doc, "docx").replace(/\.docx$/, ""),
        mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        data: await toDocx(c.doc),
        convert: true,
      })
    : await drive.upload(id, { name: /\.md$/i.test(c.title) ? c.title : `${c.title}.md`, mimeType: "text/markdown", data: Buffer.from(c.markdown, "utf8") });
  log.info("saved to drive", { kind: c.doc ? "doc" : "markdown", converted: file.mimeType === GDOC });
  res.status(201).json({ file });
});

const notionSaveBody = z.object({ parentId: z.string().min(32).max(36) });

connectRouter.post("/notion/pages", async (req, res) => {
  const id = uid(req);
  const { parentId } = notionSaveBody.parse(req.body ?? {});
  const c = await contentOf(id, saveBody.parse(req.body ?? {}));
  // The doc's own title becomes the page title; drop a leading H1 that repeats it.
  const markdown = c.markdown.replace(/^#\s+.*\n+/, "");
  const page = await notionApi.createPage(id, { parentId, title: c.title, markdown });
  log.info("saved to notion", { kind: c.doc ? "doc" : "markdown" });
  res.status(201).json({ page });
});
