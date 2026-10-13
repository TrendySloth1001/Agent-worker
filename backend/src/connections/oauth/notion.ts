import type { Client } from "@notionhq/client";
import { AppError } from "../../util/errors.js";
import { notionClient, notionStatus } from "./providers.js";
import { blocksToMarkdown, markdownToBlocks, plainText, type NotionBlock, type RichText } from "./notionMarkdown.js";
import { connectorTokens, type TokenManager } from "./tokens.js";

/**
 * Notion through the official SDK (@notionhq/client), strictly per user:
 * every call builds a Client with that user's own OAuth access token from
 * their connections row (refreshed by the token manager). There is no shared
 * integration token. Sparky only sees the pages and data sources the user
 * shared on Notion's consent screen. Search, read a page as Markdown
 * (children paginated, nested blocks followed a few levels deep), list a
 * data source's rows, and create a page under a shared parent.
 */

export type NotionItem = {
  id: string;
  /** "database" covers Notion databases and their data sources. */
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
  if (!ID_RE.test(id)) throw new AppError(400, "bad_request", "Couldn't find that Notion page.");
  return id.replace(/-/g, "").replace(/^(.{8})(.{4})(.{4})(.{4})(.{12})$/, "$1-$2-$3-$4-$5").toLowerCase();
}

function iconOf(icon: unknown): string | null {
  const i = (icon ?? {}) as Record<string, any>;
  if (i.type === "emoji") return i.emoji ?? null;
  if (i.type === "external") return i.external?.url ?? null;
  if (i.type === "file") return i.file?.url ?? null;
  return null;
}

const isCollection = (o: Record<string, any>) => o.object === "database" || o.object === "data_source";

/** Title of a page (its title property), a database or a data source. */
export function titleOf(o: Record<string, any>): string {
  if (isCollection(o)) return plainText(o.title as RichText[]) || "Untitled database";
  const props = (o.properties ?? {}) as Record<string, any>;
  for (const p of Object.values(props)) if (p?.type === "title") return plainText(p.title) || "Untitled";
  return "Untitled";
}

export function toItem(o: Record<string, any>): NotionItem {
  return {
    id: String(o.id ?? ""),
    object: isCollection(o) ? "database" : "page",
    title: titleOf(o),
    url: typeof o.url === "string" ? o.url : "",
    icon: iconOf(o.icon),
    lastEdited: typeof o.last_edited_time === "string" ? o.last_edited_time : null,
    parentType: typeof o.parent?.type === "string" ? o.parent.type : null,
  };
}

/** A Notion SDK error as the app's error; 401 is handled by the caller. */
function appErrorOf(e: unknown): AppError {
  if (e instanceof AppError) return e;
  const status = notionStatus(e);
  const message = (e as Error)?.message ?? "";
  if (status === 404) return new AppError(404, "not_found", "Notion page not found. Share it with sparky in Notion, then try again.");
  if (status === 403) return new AppError(403, "notion_forbidden", "sparky isn't allowed to do that in Notion. Check its access in Notion.");
  if (status === 429) return new AppError(429, "connector_rate_limited", "Notion is busy. Try again in a minute.", true);
  if (status === 400) return new AppError(400, "notion_bad_request", "Notion couldn't do that — check the page and try again.");
  if (!status && /timed? ?out/i.test(message)) return new AppError(504, "connector_timeout", "Notion took too long to answer.", true);
  return new AppError(502, "notion_failed", "Notion did not answer. Try again in a moment.", true);
}

export function createNotion(tokens: TokenManager = connectorTokens, f: typeof fetch = fetch) {
  /** Runs [fn] with a Client authenticated as [userId] (their own OAuth token). */
  async function as<T>(userId: string, fn: (c: Client) => Promise<T>): Promise<T> {
    const token = await tokens.accessToken(userId, "notion");
    try {
      return await fn(notionClient({ fetch: f }, token));
    } catch (e) {
      // The user's grant was revoked in Notion: offer Reconnect.
      if (notionStatus(e) === 401) return tokens.rejected(userId, "notion");
      throw appErrorOf(e);
    }
  }

  /** Pages and data sources shared with sparky, most recently edited first. */
  async function search(
    userId: string,
    opts: { q?: string; cursor?: string; kind?: "page" | "database"; pageSize?: number } = {},
  ): Promise<{ items: NotionItem[]; nextCursor: string | null }> {
    const r = await as(userId, (c) =>
      c.search({
        page_size: Math.min(Math.max(opts.pageSize ?? 30, 1), 100),
        sort: { direction: "descending", timestamp: "last_edited_time" },
        ...(opts.q?.trim() ? { query: opts.q.trim().slice(0, 200) } : {}),
        ...(opts.kind ? { filter: { property: "object" as const, value: opts.kind === "database" ? ("data_source" as const) : ("page" as const) } } : {}),
        ...(opts.cursor ? { start_cursor: opts.cursor.slice(0, 200) } : {}),
      }),
    );
    const items = (r.results as Array<Record<string, any>>).filter((o) => !o.archived && !o.in_trash).map(toItem);
    return { items, nextCursor: r.has_more ? (r.next_cursor ?? null) : null };
  }

  /** Every child block of [id] (paginated), children of children up to MAX_DEPTH. */
  async function children(c: Client, id: string, depth: number, budget: { left: number }): Promise<NotionBlock[]> {
    const out: NotionBlock[] = [];
    let cursor: string | undefined;
    do {
      const r = await c.blocks.children.list({ block_id: id, page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) });
      for (const b of r.results as unknown as NotionBlock[]) {
        if (budget.left-- <= 0) break;
        out.push(b);
      }
      cursor = r.has_more && budget.left > 0 ? (r.next_cursor ?? undefined) : undefined;
    } while (cursor);
    for (const b of out) {
      // Child pages and databases are separate documents: listed, not inlined.
      if (b.has_children && b.id && depth < MAX_DEPTH && budget.left > 0 && b.type !== "child_page" && b.type !== "child_database") {
        b.children = await children(c, b.id, depth + 1, budget);
      }
    }
    return out;
  }

  async function rows(c: Client, dataSourceId: string): Promise<string> {
    const r = await c.dataSources.query({ data_source_id: dataSourceId, page_size: 100 });
    const items = (r.results as Array<Record<string, any>>).map(toItem);
    if (!items.length) return "_This database has no rows sparky can see._";
    return items.map((i) => `- [${i.title}](${i.url})${i.lastEdited ? ` (edited ${i.lastEdited.slice(0, 10)})` : ""}`).join("\n");
  }

  /** A page, data source or database as Markdown. */
  async function read(userId: string, rawId: string, maxChars = MAX_PAGE_CHARS): Promise<NotionPage> {
    const id = checkNotionId(rawId);
    const notFound = (e: unknown) => notionStatus(e) === 404 || notionStatus(e) === 400;
    const { meta, markdown } = await as(userId, async (c) => {
      try {
        const meta = (await c.pages.retrieve({ page_id: id })) as Record<string, any>;
        return { meta, markdown: blocksToMarkdown(await children(c, id, 0, { left: MAX_BLOCKS })) };
      } catch (e) {
        if (!notFound(e)) throw e;
      }
      // Not a page: a data source (what search returns), or a database.
      try {
        const meta = (await c.dataSources.retrieve({ data_source_id: id })) as Record<string, any>;
        return { meta, markdown: await rows(c, id) };
      } catch (e) {
        if (!notFound(e)) throw e;
      }
      const db = (await c.databases.retrieve({ database_id: id })) as Record<string, any>;
      const first = (db.data_sources as Array<{ id: string }> | undefined)?.[0];
      return { meta: db, markdown: first ? await rows(c, first.id) : "" };
    });
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
    const blocks = markdownToBlocks(input.markdown) as never[];
    return as(userId, async (c) => {
      const page = (await c.pages.create({
        parent: { page_id: parent },
        properties: { title: { title: [{ type: "text", text: { content: input.title.slice(0, 200) || "Untitled" } }] } },
        children: blocks.slice(0, 100),
      })) as Record<string, any>;
      for (let i = 100; i < blocks.length; i += 100) {
        await c.blocks.children.append({ block_id: page.id, children: blocks.slice(i, i + 100) });
      }
      return toItem(page);
    });
  }

  return { search, read, createPage };
}

export const notionApi = createNotion();
