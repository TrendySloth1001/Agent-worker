import { db } from "../../db/prisma.js";
import { AppError } from "../../util/errors.js";
import { structureText } from "../structure.js";
import type { Connector } from "../types.js";

/** An uploaded document (pdf, docx, md, txt, ...). Text is the extraction stored on the file row. */
export const file: Connector = {
  async resolve(input) {
    return { uri: input };
  },
  async run(source, ctx) {
    const id = source.uri.replace(/^file:/, "");
    const row = await db().storedFile.findFirst({
      where: { id, userId: source.userId, kind: "document", status: "ready" },
      select: { id: true, name: true, text: true, mime: true, meta: true },
    });
    if (!row) throw new AppError(404, "not_found", "File not found");
    if (!row.text?.trim()) throw new AppError(422, "unprocessable", "File has no extractable text");
    ctx.setTotal(1);
    ctx.setTitle(row.name);
    const pages = Number((row.meta as Record<string, unknown> | null)?.pages) || undefined;
    await ctx.emit({ url: source.uri, title: row.name, markdown: structureText(row.text), meta: { fileId: row.id, mime: row.mime, pages } });
  },
};
