import { AppError } from "../../util/errors.js";
import { NOTION_API, NOTION_VERSION } from "./providers.js";
import { blocksToMarkdown, markdownToBlocks, plainText, type NotionBlock, type RichText } from "./notionMarkdown.js";
import { connectorTokens, providerFetch, type TokenManager } from "./tokens.js";

/**
 * Notion over the user's OAuth token: only the pages and databases they
 * shared with sparky on Notion's consent screen. Search, read a page as
 * Markdown (children paginated, nested blocks followed a few levels deep),
 * list a database's rows, and create a page under a shared parent.
 */

export type NotionItem = {
  id: string;
  object: "page" | "database";
  title: string;
  url: string;
  /** Emoji, or an https image URL. */
  icon: string | null;
  lastEdited: string | null;
  parentType: string | null;
};

export type NotionPage = NotionItem & { markdown: string; truncated: boolean };

const MAX_BLOCKS = 1500;
const MAX_DEPTH = 3;
export const MAX_PAGE_CHARS = 150_000;
const ID_RE = /^[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}$/i;

export function checkNotionId(id: string): string {
  if (!ID_RE.test(id)) throw new AppError(400, "bad_request", "Invalid Notion page id");
  return id.replace(/-/g, "").replace(/^(.{8})(.{4})(.{4})(.{4})(.{12})$/, "$1-$2-$3-$4-$5").toLowerCase();
}

function iconOf(icon: unknown): string | null {
  const i = (icon ?? {}) as Record<string, any>;
  if (i.type === "emoji") return i.emoji ?? null;
  if (i.type === "external") return i.external?.url ?? null;
  if (i.type === "file") return i.file?.url ?? null;
  return null;
}

/** Title of a page (its title property) or a database. */
export function titleOf(o: Record<string, any>): string {
  if (o.object === "database") return plainText(o.title as RichText[]) || "Untitled database";
  const props = (o.properties ?? {}) as Record<string, any>;
  for (const p of Object.values(props)) if (p?.type === "title") return plainText(p.title) || "Untitled";
  return "Untitled";
}

export function toItem(o: Record<string, any>): NotionItem {
  return {
    id: String(o.id ?? ""),
    object: o.object === "database" ? "database" : "page",
    title: titleOf(o),
    url: typeof o.url === "string" ? o.url : "",
    icon: iconOf(o.icon),
    lastEdited: typeof o.last_edited_time === "string" ? o.last_edited_time : null,
    parentType: typeof o.parent?.type === "string" ? o.parent.type : null,
  };
}

async function errorOf(res: Response): Promise<AppError> {
  const j = (await res.json().catch(() => ({}))) as { code?: string; message?: string };
  if (res.status === 404 || j.code === "object_not_found") {
    return new AppError(404, "not_found", "Notion page not found. Share it with sparky in Notion, then try again.");
  }
  if (res.status === 403) return new AppError(403, "notion_forbidden", "sparky is not allowed to do that in Notion. Check the integration's capabilities.");
  if (res.status === 400) return new AppError(400, "notion_bad_request", `Notion refused the request${j.message ? `: ${j.message.slice(0, 120)}` : ""}.`);
  return new AppError(502, "notion_failed", "Notion did not answer. Try again in a moment.", true);
}

export function createNotion(tokens: TokenManager = connectorTokens, f: typeof fetch = fetch) {
  const call = async (userId: string, path: string, init: RequestInit = {}) => {
    const headers = new Headers(init.headers);
    headers.set("Notion-Version", NOTION_VERSION);
    if (init.body) headers.set("Content-Type", "application/json");
    const res = await providerFetch(userId, "notion", `${NOTION_API}${path}`, { ...init, headers }, tokens, f);
    if (!res.ok) throw await errorOf(res);
    return (await res.json()) as Record<string, any>;
  };

  /** Pages and databases shared with sparky, most recently edited first. */
  async function search(
    userId: string,
    opts: { q?: string; cursor?: string; kind?: "page" | "database"; pageSize?: number } = {},
  ): Promise<{ items: NotionItem[]; nextCursor: string | null }> {
    const body: Record<string, unknown> = {
      page_size: Math.min(Math.max(opts.pageSize ?? 30, 1), 100),
      sort: { direction: "descending", timestamp: "last_edited_time" },
    };
    if (opts.q?.trim()) body.query = opts.q.trim().slice(0, 200);
    if (opts.kind) body.filter = { property: "object", value: opts.kind };
    if (opts.cursor) body.start_cursor = opts.cursor.slice(0, 200);
    const j = await call(userId, "/search", { method: "POST", body: JSON.stringify(body) });
    const items = ((j.results ?? []) as Array<Record<string, any>>).filter((o) => !o.archived && !o.in_trash).map(toItem);
    return { items, nextCursor: j.has_more ? (j.next_cursor ?? null) : null };
  }

  /** Every child block of [id] (paginated), children of children up to MAX_DEPTH. */
  async function children(userId: string, id: string, depth: number, budget: { left: number }): Promise<NotionBlock[]> {
    const out: NotionBlock[] = [];
    let cursor: string | undefined;
    do {
      const q = new URLSearchParams({ page_size: "100", ...(cursor ? { start_cursor: cursor } : {}) });
      const j = await call(userId, `/blocks/${id}/children?${q}`);
      for (const b of (j.results ?? []) as NotionBlock[]) {
        if (budget.left-- <= 0) break;
        out.push(b);
      }
      cursor = j.has_more && budget.left > 0 ? j.next_cursor : undefined;
    } while (cursor);
    for (const b of out) {
      // Child pages and databases are separate documents: listed, not inlined.
      if (b.has_children && b.id && depth < MAX_DEPTH && budget.left > 0 && b.type !== "child_page" && b.type !== "child_database") {
        b.children = await children(userId, b.id, depth + 1, budget);
      }
    }
    return out;
  }

  async function database(userId: string, id: string): Promise<string> {
    const j = await call(userId, `/databases/${id}/query`, { method: "POST", body: JSON.stringify({ page_size: 100 }) });
    const rows = ((j.results ?? []) as Array<Record<string, any>>).map(toItem);
    if (!rows.length) return "_This database has no rows sparky can see._";
    return rows.map((r) => `- [${r.title}](${r.url})${r.lastEdited ? ` (edited ${r.lastEdited.slice(0, 10)})` : ""}`).join("\n");
  }

  /** A page (or database) as Markdown. */
  async function read(userId: string, rawId: string, maxChars = MAX_PAGE_CHARS): Promise<NotionPage> {
    const id = checkNotionId(rawId);
    let meta: Record<string, any>;
    let markdown: string;
    try {
      meta = await call(userId, `/pages/${id}`);
      markdown = blocksToMarkdown(await children(userId, id, 0, { left: MAX_BLOCKS }));
    } catch (e) {
      // Not a page: maybe a database.
      if (!(e instanceof AppError) || e.status !== 404) throw e;
      meta = await call(userId, `/databases/${id}`);
      markdown = await database(userId, id);
    }
    const item = toItem(meta);
    const full = markdown.trim();
    return { ...item, markdown: full.slice(0, maxChars), truncated: full.length > maxChars };
  }

  /**
   * Creates a page titled [title] under the shared page [parentId] with
   * [markdown] as its content (appended in batches of 100 blocks).
   */
  async function createPage(userId: string, input: { parentId: string; title: string; markdown: string }): Promise<NotionItem> {
    const parent = checkNotionId(input.parentId);
    const blocks = markdownToBlocks(input.markdown);
    const page = await call(userId, "/pages", {
      method: "POST",
      body: JSON.stringify({
        parent: { page_id: parent },
        properties: { title: { title: [{ type: "text", text: { content: input.title.slice(0, 200) || "Untitled" } }] } },
        children: blocks.slice(0, 100),
      }),
    });
    for (let i = 100; i < blocks.length; i += 100) {
      await call(userId, `/blocks/${page.id}/children`, { method: "PATCH", body: JSON.stringify({ children: blocks.slice(i, i + 100) }) });
    }
    return toItem(page);
  }

  return { search, read, createPage };
}

export const notionApi = createNotion();
