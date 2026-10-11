import { Readability } from "@mozilla/readability";
import { parseHTML } from "linkedom";
import TurndownService from "turndown";

export type Extracted = { title: string | null; markdown: string; links: string[] };

const td = new TurndownService({ headingStyle: "atx", codeBlockStyle: "fenced", bulletListMarker: "-", emDelimiter: "*" });
td.remove(["script", "style", "noscript", "iframe", "form", "button"]);
td.remove((n) => n.nodeName.toLowerCase() === "svg");
td.addRule("fencedLang", {
  filter: (node) => node.nodeName === "PRE" && !!(node as any).querySelector?.("code"),
  replacement: (_c, node) => {
    const code = (node as any).querySelector("code");
    const cls = `${code.getAttribute("class") ?? ""} ${(node as any).getAttribute?.("class") ?? ""}`;
    const lang = cls.match(/(?:language|lang|highlight-source|brush:)[-\s]?([a-z0-9+#]+)/i)?.[1] ?? "";
    const text = String(code.textContent ?? "").replace(/\n+$/, "");
    const fence = text.includes("```") ? "~~~" : "```";
    return `\n\n${fence}${lang}\n${text}\n${fence}\n\n`;
  },
});

export function looksLikeHtml(contentType: string, body: string): boolean {
  return /html/i.test(contentType) || /^\s*(<!doctype html|<html)/i.test(body.slice(0, 200));
}

export function extractHtml(html: string, baseUrl: string): Extracted {
  const { document } = parseHTML(html);
  const links: string[] = [];
  for (const a of Array.from(document.querySelectorAll("a[href]")) as any[]) {
    try {
      const u = new URL(a.getAttribute("href"), baseUrl);
      if (u.protocol === "http:" || u.protocol === "https:") {
        u.hash = "";
        links.push(u.toString());
      }
    } catch {
      /* ignore */
    }
  }
  const docTitle = (document.querySelector("title")?.textContent ?? "").trim() || null;

  let title = docTitle;
  let contentHtml: string | null = null;
  try {
    // Readability mutates the document; run on a clone-by-reparse to keep `document` usable for fallback.
    const { document: d2 } = parseHTML(html);
    const reader = new Readability(d2 as any, { keepClasses: true, charThreshold: 200 });
    const art = reader.parse();
    if (art?.content && (art.textContent?.trim().length ?? 0) > 200) {
      contentHtml = art.content;
      title = art.title?.trim() || title;
    }
  } catch {
    /* fall through */
  }
  if (!contentHtml) {
    const main = document.querySelector("main, article, [role=main]") ?? document.body;
    contentHtml = (main as any)?.innerHTML ?? "";
  }
  const markdown = td.turndown(contentHtml ?? "").replace(/\n{3,}/g, "\n\n").trim();
  return { title, markdown, links };
}

export function htmlToMarkdown(html: string): string {
  return td.turndown(html).replace(/\n{3,}/g, "\n\n").trim();
}

/** Strip HTML to plain markdown for API bodies (StackOverflow, HN). */
export function snippetHtmlToMarkdown(html: string): string {
  const { document } = parseHTML(`<div id="r">${html}</div>`);
  return td.turndown((document.getElementById("r") as any)?.innerHTML ?? html).replace(/\n{3,}/g, "\n\n").trim();
}
