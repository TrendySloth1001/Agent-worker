import { db } from "../../db/prisma.js";
import { userCrypto } from "../../crypto/userData.js";
import { REFERENCES_ID } from "../../docs/types.js";
import { AppError } from "../../util/errors.js";
import type { Connector } from "../types.js";

/** Citation tags, image placeholders and directives that mean nothing outside the doc. */
export function cleanDocMarkdown(md: string): string {
  return md
    .replace(/\{\{[^}]*\}\}/g, "")
    .replace(/\s?\[[KWDG]\d+\](?:\[[KWDG]\d+\])*/g, "")
    .replace(/!\[[^\]]*\]\([^)]*\)/g, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/**
 * A generated DOC-mode document. One knowledge-base document per section (url
 * `doc:<id>#<sectionId>`), so a hit points at the section; the summary and the
 * section heading are indexed with the body.
 */
export const doc: Connector = {
  async resolve(input) {
    return { uri: input };
  },
  async run(source, ctx) {
    const id = source.uri.replace(/^doc:/, "");
    if (!source.userId) throw new AppError(404, "not_found", "Doc not found");
    const row = await db().doc.findFirst({
      where: { id, userId: source.userId },
      select: { id: true, title: true, summary: true, sections: { orderBy: { ord: "asc" }, select: { sectionId: true, heading: true, level: true, markdown: true, status: true } } },
    });
    if (!row) throw new AppError(404, "not_found", "Doc not found");
    const c = await userCrypto(source.userId);
    const summary = c.open("docs", "summary", row.summary);
    const title = c.open("docs", "title", row.title) || "Untitled doc";
    const sections = row.sections
      .map((s) => ({ ...s, heading: c.open("doc_sections", "heading", s.heading), markdown: c.open("doc_sections", "markdown", s.markdown) }))
      .filter((s) => s.sectionId !== REFERENCES_ID && s.status === "done" && s.markdown.trim());
    ctx.setTotal(sections.length + (summary.trim() ? 1 : 0));
    ctx.setTitle(title);
    if (summary.trim()) {
      await ctx.emit({ url: `doc:${row.id}#summary`, title, markdown: `## Summary\n\n${cleanDocMarkdown(summary)}`, meta: { docId: row.id, sectionId: "summary", heading: "Summary" } });
    }
    for (const s of sections) {
      const body = cleanDocMarkdown(s.markdown);
      // The section body may already start with its own heading.
      const markdown = /^#{1,6}\s/.test(body) ? body : `## ${s.heading}\n\n${body}`;
      await ctx.emit({ url: `doc:${row.id}#${s.sectionId}`, title, markdown, meta: { docId: row.id, sectionId: s.sectionId, heading: s.heading } });
    }
    if (sections.length === 0 && !summary.trim()) throw new AppError(422, "unprocessable", "Doc has no finished sections yet");
  },
};
