import { AppError } from "../../util/errors.js";
import { drive } from "../../connections/oauth/drive.js";
import { notionApi } from "../../connections/oauth/notion.js";
import type { Connector } from "../types.js";

/**
 * Files and pages from the connected apps, indexed with the owner's token at
 * ingest time (so a refresh re-reads the current version). Created by
 * POST /connect/google_drive/files/:id/knowledge and /connect/notion/pages/:id/knowledge,
 * never added by URL.
 */

const owner = (userId: string | null) => {
  if (!userId) throw new AppError(403, "forbidden", "Connected apps need an account");
  return userId;
};

/** uri `gdrive:<fileId>`. */
export const googleDrive: Connector = {
  async resolve(input) {
    return { uri: input };
  },
  async run(source, ctx) {
    const id = source.uri.replace(/^gdrive:/, "");
    ctx.setTotal(1);
    const c = await drive.read(owner(source.userId), id);
    if (c.format === "metadata") throw new AppError(422, "unprocessable", "sparky cannot read this kind of Drive file");
    ctx.setTitle(c.file.name);
    const markdown = c.format === "csv" ? `# ${c.file.name}\n\n\`\`\`csv\n${c.text}\n\`\`\`` : c.text;
    await ctx.emit({ url: c.file.webViewLink ?? source.uri, title: c.file.name, markdown, meta: { driveFileId: c.file.id, mimeType: c.file.mimeType } });
  },
};

/** uri `notion:<pageId>`. */
export const notion: Connector = {
  async resolve(input) {
    return { uri: input };
  },
  async run(source, ctx) {
    const id = source.uri.replace(/^notion:/, "");
    ctx.setTotal(1);
    const page = await notionApi.read(owner(source.userId), id);
    if (!page.markdown.trim()) throw new AppError(422, "unprocessable", "This Notion page is empty");
    ctx.setTitle(page.title);
    await ctx.emit({ url: page.url || source.uri, title: page.title, markdown: `# ${page.title}\n\n${page.markdown}`, meta: { notionPageId: page.id } });
  },
};
