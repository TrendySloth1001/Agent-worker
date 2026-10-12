import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import type { Content, PhrasingContent, Root } from "mdast";

/**
 * Notion blocks ↔ Markdown. Reading: every common block type, nested
 * children indented, rich text with its annotations and links. Writing (Save
 * to Notion): Markdown parsed with remark into paragraphs, headings, lists,
 * to-dos, quotes, code, dividers and simple tables, with inline bold, italic,
 * code, strikethrough and links. Notion caps a rich-text item at 2000
 * characters, so long runs are split.
 */

export type RichText = {
  type?: string;
  plain_text?: string;
  href?: string | null;
  text?: { content: string; link?: { url: string } | null };
  annotations?: { bold?: boolean; italic?: boolean; strikethrough?: boolean; underline?: boolean; code?: boolean };
  equation?: { expression?: string };
};

export type NotionBlock = {
  id?: string;
  type: string;
  has_children?: boolean;
  /** Filled in by the reader for blocks with children. */
  children?: NotionBlock[];
  [key: string]: unknown;
};

// ---- reading ----------------------------------------------------------------

export function richToMarkdown(rt: RichText[] | undefined): string {
  if (!Array.isArray(rt)) return "";
  return rt
    .map((r) => {
      if (r.type === "equation") return `$${r.equation?.expression ?? r.plain_text ?? ""}$`;
      let t = r.plain_text ?? r.text?.content ?? "";
      if (!t) return "";
      const a = r.annotations ?? {};
      if (a.code) t = `\`${t}\``;
      else {
        // Markdown markers must hug the text: keep outer spaces outside.
        const lead = t.match(/^\s*/)![0];
        const trail = t.match(/\s*$/)![0];
        let core = t.trim();
        if (core) {
          if (a.bold) core = `**${core}**`;
          if (a.italic) core = `*${core}*`;
          if (a.strikethrough) core = `~~${core}~~`;
        }
        t = lead + core + trail;
      }
      const href = r.href ?? r.text?.link?.url;
      return href ? `[${t}](${href})` : t;
    })
    .join("");
}

export const plainText = (rt: RichText[] | undefined) => (Array.isArray(rt) ? rt.map((r) => r.plain_text ?? r.text?.content ?? "").join("") : "");

const fileUrl = (v: unknown): string | null => {
  const o = (v ?? {}) as Record<string, any>;
  return o.type === "external" ? (o.external?.url ?? null) : o.type === "file" ? (o.file?.url ?? null) : null;
};

const LIST_TYPES = new Set(["bulleted_list_item", "numbered_list_item", "to_do", "toggle"]);

/** Markdown for a list of blocks; [depth] indents nested children. */
export function blocksToMarkdown(blocks: NotionBlock[], depth = 0): string {
  const pad = "  ".repeat(depth);
  // One entry per block; list items join with a single newline, the rest with a blank line.
  const out: Array<{ text: string; list: boolean }> = [];
  let n = 0;
  for (const b of blocks) {
    const v = (b[b.type] ?? {}) as Record<string, any>;
    const text = richToMarkdown(v.rich_text);
    n = b.type === "numbered_list_item" ? n + 1 : 0;
    let line: string | null = null;
    let nestKids = true;
    switch (b.type) {
      case "paragraph":
        line = text;
        break;
      case "heading_1":
        line = `# ${text}`;
        break;
      case "heading_2":
        line = `## ${text}`;
        break;
      case "heading_3":
        line = `### ${text}`;
        break;
      case "bulleted_list_item":
      case "toggle":
        line = `- ${text}`;
        break;
      case "numbered_list_item":
        line = `${n}. ${text}`;
        break;
      case "to_do":
        line = `- [${v.checked ? "x" : " "}] ${text}`;
        break;
      case "quote":
        line = text
          .split("\n")
          .map((l) => `> ${l}`)
          .join("\n");
        break;
      case "callout": {
        const icon = v.icon?.type === "emoji" ? `${v.icon.emoji} ` : "";
        line = `> ${icon}${text}`;
        break;
      }
      case "code":
        line = `\`\`\`${v.language && v.language !== "plain text" ? v.language : ""}\n${plainText(v.rich_text)}\n\`\`\``;
        break;
      case "equation":
        line = `$$\n${v.expression ?? ""}\n$$`;
        break;
      case "divider":
        line = "---";
        break;
      case "image": {
        const url = fileUrl(v);
        line = url ? `![${plainText(v.caption) || "image"}](${url})` : null;
        break;
      }
      case "bookmark":
      case "embed":
      case "link_preview":
        line = v.url ? `[${plainText(v.caption) || v.url}](${v.url})` : null;
        break;
      case "file":
      case "pdf":
      case "video":
      case "audio": {
        const url = fileUrl(v);
        line = url ? `[${plainText(v.caption) || v.name || b.type}](${url})` : null;
        break;
      }
      case "child_page":
        line = `📄 ${v.title ?? "Untitled"}`;
        break;
      case "child_database":
        line = `🗂 ${v.title ?? "Untitled database"}`;
        break;
      case "table": {
        const rows = (b.children ?? []).filter((r) => r.type === "table_row");
        if (rows.length) {
          const cells = rows.map((r) =>
            (((r.table_row as any)?.cells ?? []) as RichText[][]).map((c) => richToMarkdown(c).replace(/\|/g, "\\|").replace(/\n/g, " ")),
          );
          const width = Math.max(...cells.map((c) => c.length));
          const row = (c: string[]) => `| ${Array.from({ length: width }, (_, i) => c[i] ?? "").join(" | ")} |`;
          line = [row(cells[0]), `| ${Array.from({ length: width }, () => "---").join(" | ")} |`, ...cells.slice(1).map(row)].join("\n");
        }
        nestKids = false;
        break;
      }
      case "column_list":
      case "column":
      case "synced_block":
      case "template":
        // Containers: their children are the content, at the same depth.
        if (b.children?.length) out.push({ text: blocksToMarkdown(b.children, depth), list: false });
        continue;
      default:
        line = text || null;
    }
    if (!line) continue;
    let entry = line
      .split("\n")
      .map((l) => pad + l)
      .join("\n");
    if (nestKids && b.children?.length) entry += `\n${blocksToMarkdown(b.children, depth + 1)}`;
    out.push({ text: entry, list: LIST_TYPES.has(b.type) });
  }
  return out
    .map((e, i) => (i === 0 ? "" : e.list && out[i - 1].list ? "\n" : "\n\n") + e.text)
    .join("");
}

// ---- writing ----------------------------------------------------------------

export const RICH_MAX = 2000;
type Ann = { bold?: boolean; italic?: boolean; strikethrough?: boolean; code?: boolean };
export type OutRich = { type: "text"; text: { content: string; link?: { url: string } }; annotations?: Ann };

function pushRich(out: OutRich[], content: string, ann: Ann, link?: string) {
  for (let i = 0; i < content.length; i += RICH_MAX) {
    const piece = content.slice(i, i + RICH_MAX);
    const item: OutRich = { type: "text", text: { content: piece, ...(link && /^https?:\/\//.test(link) ? { link: { url: link } } : {}) } };
    if (ann.bold || ann.italic || ann.strikethrough || ann.code) item.annotations = { ...ann };
    out.push(item);
  }
}

function phrasing(nodes: PhrasingContent[], ann: Ann = {}, link?: string, out: OutRich[] = []): OutRich[] {
  for (const n of nodes) {
    switch (n.type) {
      case "text":
        pushRich(out, n.value, ann, link);
        break;
      case "inlineCode":
        pushRich(out, n.value, { ...ann, code: true }, link);
        break;
      case "strong":
        phrasing(n.children, { ...ann, bold: true }, link, out);
        break;
      case "emphasis":
        phrasing(n.children, { ...ann, italic: true }, link, out);
        break;
      case "delete":
        phrasing(n.children, { ...ann, strikethrough: true }, link, out);
        break;
      case "link":
        phrasing(n.children, ann, n.url, out);
        break;
      case "break":
        pushRich(out, "\n", ann, link);
        break;
      case "image":
        if (/^https?:\/\//.test(n.url)) pushRich(out, n.alt || n.url, ann, n.url);
        break;
      default:
        if ("value" in n && typeof n.value === "string") pushRich(out, n.value, ann, link);
        else if ("children" in n) phrasing(n.children as PhrasingContent[], ann, link, out);
    }
  }
  return out;
}

const NOTION_LANGS = new Set([
  "bash", "c", "c#", "c++", "css", "dart", "diff", "docker", "go", "graphql", "html", "java", "javascript", "json", "kotlin",
  "markdown", "php", "python", "ruby", "rust", "scala", "shell", "sql", "swift", "typescript", "xml", "yaml",
]);
const LANG_ALIAS: Record<string, string> = { js: "javascript", ts: "typescript", sh: "shell", py: "python", yml: "yaml", md: "markdown", dockerfile: "docker", cpp: "c++", csharp: "c#" };

const block = (type: string, body: Record<string, unknown>, children?: NotionBlock[]): NotionBlock => ({
  object: "block",
  type,
  [type]: children?.length ? { ...body, children } : body,
});

function nodeBlocks(n: Content): NotionBlock[] {
  switch (n.type) {
    case "heading": {
      const level = Math.min(Math.max(n.depth, 1), 3);
      return [block(`heading_${level}`, { rich_text: phrasing(n.children) })];
    }
    case "paragraph": {
      const rt = phrasing(n.children);
      return rt.length ? [block("paragraph", { rich_text: rt })] : [];
    }
    case "blockquote":
      return [block("quote", { rich_text: n.children.flatMap((c) => (c.type === "paragraph" ? phrasing(c.children) : [])) })];
    case "code": {
      const raw = (n.lang ?? "").toLowerCase();
      const lang = LANG_ALIAS[raw] ?? raw;
      const rt: OutRich[] = [];
      pushRich(rt, n.value, {});
      return [block("code", { rich_text: rt, language: NOTION_LANGS.has(lang) ? lang : "plain text" })];
    }
    case "thematicBreak":
      return [block("divider", {})];
    case "list":
      return n.children.map((item) => {
        const [first, ...rest] = item.children;
        const rt = first && first.type === "paragraph" ? phrasing(first.children) : [];
        const kids = (first && first.type !== "paragraph" ? [first, ...rest] : rest).flatMap(nodeBlocks).slice(0, 100);
        if (typeof item.checked === "boolean") return block("to_do", { rich_text: rt, checked: item.checked }, kids);
        return block(n.ordered ? "numbered_list_item" : "bulleted_list_item", { rich_text: rt }, kids);
      });
    case "table": {
      const rows = n.children.map((r) => r.children.map((c) => phrasing(c.children)));
      const width = Math.max(1, ...rows.map((r) => r.length));
      return [
        block("table", { table_width: width, has_column_header: true, has_row_header: false }, rows.slice(0, 100).map((cells) => ({
          object: "block",
          type: "table_row",
          table_row: { cells: Array.from({ length: width }, (_, i) => cells[i] ?? []) },
        }))),
      ];
    }
    case "html": {
      const rt: OutRich[] = [];
      pushRich(rt, n.value, {});
      return [block("paragraph", { rich_text: rt })];
    }
    default:
      return [];
  }
}

/** Markdown → Notion block objects (top level; nested children inline). */
export function markdownToBlocks(md: string): NotionBlock[] {
  const tree = unified().use(remarkParse).use(remarkGfm).parse(md) as Root;
  return tree.children.flatMap((c) => nodeBlocks(c as Content));
}
