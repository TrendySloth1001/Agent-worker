// Export a document as Markdown or DOCX. Phase 1: mermaid and math are kept as
// captioned code; pictures become links in DOCX.
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import type { Root, RootContent, PhrasingContent, ListItem, TableRow } from "mdast";
import {
  AlignmentType,
  BorderStyle,
  Document,
  ExternalHyperlink,
  HeadingLevel,
  Packer,
  Paragraph,
  ShadingType,
  Table,
  TableCell,
  TableRow as DocxRow,
  TextRun,
  WidthType,
  type ParagraphChild,
} from "docx";
import { REFERENCES_ID, TAKEAWAYS_ID, type DocState } from "./types.js";

/** Section body with {{image:...}} placeholders resolved to Markdown images (or dropped). */
function resolveImages(md: string, images: DocState["sections"][number]["images"]): string {
  return md.replace(/^[ \t]*\{\{image:([^}|]+)(?:\|([^}]*))?\}\}[ \t]*$/gm, (_m, q: string, cap?: string) => {
    const img = images.find((i) => i.query === q.trim()) ?? images[0];
    if (!img) return "";
    const alt = (cap ?? img.caption ?? img.title ?? q).replace(/[[\]]/g, "").trim();
    return `![${alt}](${img.url})\n*${alt}* (${img.site || "source"}: ${img.sourceUrl})`;
  });
}

const TAG_RUN = /[ \t]*\[[KWDG]\d+\](?:[ \t,]*\[[KWDG]\d+\])*/g;
const TAG = /\[([KWDG]\d+)\]/g;
/** Private-use markers around a citation superscript in DOCX text; `runs` turns them into superscript runs. */
const SUP_OPEN = "\uE000";
const SUP_CLOSE = "\uE001";
const NAME_MAX = 24;
const SECOND_LEVEL = new Set(["co", "com", "org", "net", "gov", "edu", "ac"]);

const clip = (s: string) => (s.length <= NAME_MAX ? s : s.slice(0, NAME_MAX));
const hostFromUrl = (url: string) => {
  try {
    return new URL(url).hostname.toLowerCase();
  } catch {
    return "";
  }
};
const hostOf = (s: { site: string; url: string }) => {
  let host = s.site.trim().toLowerCase();
  if (host.includes("://")) host = hostFromUrl(host);
  if (!host.includes(".")) host = hostFromUrl(s.url) || host;
  return host.replace(/^www\./, "");
};

/** Short readable name for a source, like the app's citation chips: `developer.mozilla.org` -> `mozilla`. */
export function siteName(s: { kind: string; title: string; url: string; site: string }): string {
  if (s.kind === "file" || (s.kind === "kb" && (s.site === "doc" || s.site === "file" || !s.url))) return clip(s.title.trim() || "document");
  const host = hostOf(s);
  if (host === "github.com") {
    const parts = (() => {
      try {
        return new URL(s.url).pathname.split("/").filter(Boolean);
      } catch {
        return [];
      }
    })();
    if (parts.length >= 2) return clip(parts[1]);
    if (parts.length === 1) return clip(parts[0]);
  }
  if (!host.includes(".")) return clip(host || s.site.trim() || s.title.trim() || "source");
  const parts = host.split(".");
  if (parts.length >= 3 && parts[parts.length - 1].length === 2 && SECOND_LEVEL.has(parts[parts.length - 2])) parts.length -= 2;
  else if (parts.length > 1) parts.pop();
  return clip(parts[parts.length - 1]);
}

/** Cited source ids across the body sections, first use first. */
export function citationOrder(doc: DocState): string[] {
  const known = new Set(doc.sources.map((s) => s.id));
  const out: string[] = [];
  const body = [...doc.sections].sort((a, b) => a.ord - b.ord).filter((s) => s.sectionId !== REFERENCES_ID);
  for (const sec of body) {
    const ids = sec.usedIds.length ? sec.usedIds : [...sec.markdown.matchAll(TAG)].map((m) => m[1]);
    for (const id of ids) if (known.has(id) && !out.includes(id)) out.push(id);
  }
  return out;
}

export type CiteMode = "markdown" | "docx";

/** Citation tags as numbers that point into the numbered references list; unknown tags vanish. Adjacent tags share one mark. */
export function replaceCitations(md: string, order: string[], mode: CiteMode): string {
  const num = new Map(order.map((id, i) => [id, i + 1]));
  return md.replace(TAG_RUN, (run) => {
    const nums = [...new Set([...run.matchAll(TAG)].map((m) => num.get(m[1])).filter((n): n is number => n != null))].sort((a, b) => a - b);
    if (!nums.length) return "";
    if (mode === "docx") return `${SUP_OPEN}${nums.join(",")}${SUP_CLOSE}`;
    return `<sup>${nums.map((n) => `[${n}](#ref-${n})`).join(",")}</sup>`;
  });
}

/** Numbered references: site name, title and link; anchors let the in-text numbers jump here. */
export function referencesList(doc: DocState, order: string[], mode: CiteMode): string {
  const byId = new Map(doc.sources.map((s) => [s.id, s]));
  return order
    .map((id, i) => {
      const s = byId.get(id)!;
      const title = (s.title || s.url).replace(/[[\]]/g, "").replace(/\s+/g, " ").trim();
      const url = s.url.replace(/\(/g, "%28").replace(/\)/g, "%29").replace(/ /g, "%20");
      const what = url && s.kind === "web" ? `[${title}](${url})` : `${title}${s.kind === "kb" || !url ? " (knowledge base)" : ""}`;
      const anchor = mode === "markdown" ? `<a id="ref-${i + 1}"></a>` : "";
      return `${i + 1}. ${anchor}**${siteName(s)}** \u00b7 ${what}`;
    })
    .join("\n");
}

export function toMarkdown(doc: DocState, mode: CiteMode = "markdown"): string {
  const title = doc.title || doc.outline?.title || "Untitled document";
  const out: string[] = [`# ${title}`];
  const order = citationOrder(doc);
  const cite = (md: string) => replaceCitations(md, order, mode);
  if (doc.outline?.subtitle) out.push(`*${doc.outline.subtitle}*`);
  if (doc.summary) out.push(`> ${cite(doc.summary)}`);
  const sections = [...doc.sections].sort((a, b) => a.ord - b.ord);
  const takeaways = sections.find((s) => s.sectionId === TAKEAWAYS_ID);
  for (const s of sections) {
    if (s.sectionId === TAKEAWAYS_ID) continue;
    if (s.sectionId === REFERENCES_ID) {
      if (takeaways?.markdown) out.push(`## ${takeaways.heading}\n\n${cite(takeaways.markdown)}`);
      const list = order.length ? referencesList(doc, order, mode) : cite(s.markdown);
      if (list) out.push(`## ${s.heading}\n\n${list}`);
      continue;
    }
    const body = s.status === "done" || s.markdown ? cite(resolveImages(s.markdown, s.images)) : "";
    out.push(`## ${s.heading}\n\n${body || "_This section has not been written yet._"}`);
  }
  if (!sections.some((s) => s.sectionId === REFERENCES_ID) && takeaways?.markdown) out.push(`## ${takeaways.heading}\n\n${cite(takeaways.markdown)}`);
  return out.join("\n\n").replace(/\n{3,}/g, "\n\n").trim() + "\n";
}

// ---- DOCX -------------------------------------------------------------------------

type Style = { bold?: boolean; italics?: boolean; code?: boolean; strike?: boolean };

const MONO = "Courier New";

function runs(nodes: PhrasingContent[], style: Style = {}): ParagraphChild[] {
  const out: ParagraphChild[] = [];
  for (const n of nodes) {
    switch (n.type) {
      case "text":
        // Citation numbers arrive wrapped in private-use markers and become real superscript.
        n.value
          .replace(/\n/g, " ")
          .split(new RegExp(`${SUP_OPEN}([^${SUP_CLOSE}]*)${SUP_CLOSE}`))
          .forEach((part, i) => {
            if (!part) return;
            out.push(new TextRun({ text: part, bold: style.bold, italics: style.italics, strike: style.strike, font: style.code ? MONO : undefined, superScript: i % 2 === 1 || undefined }));
          });
        break;
      case "strong":
        out.push(...runs(n.children, { ...style, bold: true }));
        break;
      case "emphasis":
        out.push(...runs(n.children, { ...style, italics: true }));
        break;
      case "delete":
        out.push(...runs(n.children, { ...style, strike: true }));
        break;
      case "inlineCode":
        out.push(new TextRun({ text: n.value, font: MONO, bold: style.bold, italics: style.italics }));
        break;
      case "break":
        out.push(new TextRun({ text: "", break: 1 }));
        break;
      case "link":
        out.push(new ExternalHyperlink({ link: n.url, children: [new TextRun({ text: plain(n.children) || n.url, style: "Hyperlink" })] }));
        break;
      case "image":
        out.push(new ExternalHyperlink({ link: n.url, children: [new TextRun({ text: `[Image: ${n.alt || n.url}]`, style: "Hyperlink" })] }));
        break;
      case "html":
        break;
      default:
        if ("children" in n) out.push(...runs((n as { children: PhrasingContent[] }).children, style));
        else if ("value" in n) out.push(new TextRun({ text: String((n as { value: string }).value) }));
    }
  }
  return out;
}

function plain(nodes: PhrasingContent[]): string {
  return nodes.map((n) => ("value" in n ? String(n.value) : "children" in n ? plain((n as { children: PhrasingContent[] }).children) : "")).join("");
}

const HEADINGS = [HeadingLevel.HEADING_1, HeadingLevel.HEADING_2, HeadingLevel.HEADING_3, HeadingLevel.HEADING_4, HeadingLevel.HEADING_5, HeadingLevel.HEADING_6];

function blocks(nodes: RootContent[], depth = 0, quote = false): Array<Paragraph | Table> {
  const out: Array<Paragraph | Table> = [];
  for (const n of nodes) {
    switch (n.type) {
      case "heading":
        out.push(new Paragraph({ heading: HEADINGS[Math.min(n.depth, 6) - 1], children: runs(n.children) }));
        break;
      case "paragraph": {
        const raw = plain(n.children).trim();
        if (/^\$\$[\s\S]+\$\$$/.test(raw)) {
          out.push(new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: raw.slice(2, -2).trim(), font: MONO })] }));
          break;
        }
        // GitHub callout marker "[!NOTE]" becomes a bold label.
        const first = n.children[0];
        if (quote && first?.type === "text" && /^\[!(\w+)\]/.test(first.value)) {
          const label = first.value.match(/^\[!(\w+)\]/)![1];
          const rest = { ...first, value: first.value.replace(/^\[!\w+\]\s*/, "") };
          out.push(new Paragraph({ indent: { left: 400 }, children: [new TextRun({ text: `${label.toUpperCase()}: `, bold: true }), ...runs([rest, ...n.children.slice(1)], { italics: true })] }));
        } else out.push(new Paragraph({ indent: quote ? { left: 400 } : undefined, children: runs(n.children, quote ? { italics: true } : {}) }));
        break;
      }
      case "list":
        n.children.forEach((item: ListItem, i) => {
          for (const [k, child] of item.children.entries()) {
            if (child.type === "paragraph" && k === 0) {
              const marker = n.ordered ? `${(n.start ?? 1) + i}. ` : "";
              out.push(
                new Paragraph({
                  ...(n.ordered ? { indent: { left: 360 * (depth + 1), hanging: 260 } } : { bullet: { level: Math.min(depth, 8) } }),
                  children: [...(marker ? [new TextRun(marker)] : []), ...(item.checked != null ? [new TextRun(item.checked ? "[x] " : "[ ] ")] : []), ...runs(child.children)],
                }),
              );
            } else out.push(...blocks([child], depth + 1, quote));
          }
        });
        break;
      case "code": {
        const lang = (n.lang ?? "").toLowerCase();
        if (lang === "mermaid") out.push(new Paragraph({ children: [new TextRun({ text: "Diagram (Mermaid source):", italics: true, bold: true })] }));
        n.value.split("\n").forEach((line) =>
          out.push(new Paragraph({ shading: { type: ShadingType.CLEAR, color: "auto", fill: "F2F2F2" }, children: [new TextRun({ text: line || " ", font: MONO, size: 18 })] })),
        );
        break;
      }
      case "blockquote":
        out.push(...blocks(n.children, depth, true));
        break;
      case "table":
        out.push(
          new Table({
            width: { size: 100, type: WidthType.PERCENTAGE },
            rows: n.children.map(
              (row: TableRow, r) =>
                new DocxRow({
                  tableHeader: r === 0,
                  children: row.children.map(
                    (cell) =>
                      new TableCell({
                        borders: { top: border, bottom: border, left: border, right: border },
                        children: [new Paragraph({ children: runs(cell.children, r === 0 ? { bold: true } : {}) })],
                      }),
                  ),
                }),
            ),
          }),
        );
        out.push(new Paragraph({ children: [] }));
        break;
      case "thematicBreak":
        out.push(new Paragraph({ border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: "999999", space: 1 } }, children: [] }));
        break;
      case "html":
        break;
      default:
        if ("children" in n) out.push(...blocks((n as { children: RootContent[] }).children, depth, quote));
    }
  }
  return out;
}

const border = { style: BorderStyle.SINGLE, size: 4, color: "BBBBBB" };

export async function toDocx(doc: DocState): Promise<Buffer> {
  const tree = unified().use(remarkParse).use(remarkGfm).parse(toMarkdown(doc, "docx")) as Root;
  const children = blocks(tree.children);
  const file = new Document({
    creator: "Sparky",
    title: doc.title || "Document",
    description: doc.outline?.subtitle ?? "",
    styles: { default: { document: { run: { font: "Calibri", size: 22 } } } },
    sections: [{ children }],
  });
  return Packer.toBuffer(file);
}

/** A safe file name for Content-Disposition. */
export function fileName(doc: DocState, ext: string): string {
  const base = (doc.title || "document").replace(/[^\p{L}\p{N} _-]+/gu, "").trim().replace(/\s+/g, "-").slice(0, 80) || "document";
  return `${base}.${ext}`;
}
