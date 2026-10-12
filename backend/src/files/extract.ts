import mammoth from "mammoth";
import ExcelJS from "exceljs";
import { htmlToMarkdown } from "../ingest/extract.js";
import { extOf } from "./kinds.js";

export const MAX_TEXT_CHARS = 400_000;

export type Extracted = { text: string; pages?: number };

async function pdfText(buf: Buffer): Promise<Extracted> {
  const pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  const task = pdfjs.getDocument({ data: new Uint8Array(buf), useSystemFonts: true, verbosity: 0 });
  const doc = await task.promise;
  const parts: string[] = [];
  let size = 0;
  try {
    for (let p = 1; p <= doc.numPages && size < MAX_TEXT_CHARS; p++) {
      const page = await doc.getPage(p);
      const content = await page.getTextContent();
      let line = "";
      const lines: string[] = [];
      for (const it of content.items as Array<{ str?: string; hasEOL?: boolean }>) {
        if (typeof it.str !== "string") continue;
        line += it.str;
        if (it.hasEOL) (lines.push(line), (line = ""));
      }
      if (line) lines.push(line);
      const t = lines.join("\n").trim();
      parts.push(`--- Page ${p} ---\n${t}`);
      size += t.length;
      page.cleanup();
    }
    return { text: parts.join("\n\n"), pages: doc.numPages };
  } finally {
    await task.destroy().catch(() => {});
  }
}

/** Every sheet as CSV-like text: "--- Sheet: name ---" then one line per non-empty row. */
async function sheetsText(buf: Buffer): Promise<string> {
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(buf as unknown as ArrayBuffer);
  const cell = (v: ExcelJS.CellValue): string => {
    if (v === null || v === undefined) return "";
    if (v instanceof Date) return v.toISOString().slice(0, 10);
    if (typeof v === "object") {
      if ("result" in v) return cell(v.result as ExcelJS.CellValue);
      if ("text" in v) return String(v.text);
      if ("richText" in v) return v.richText.map((r) => r.text).join("");
      if ("hyperlink" in v) return String(v.hyperlink);
      return "";
    }
    const s = String(v);
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return wb.worksheets
    .map((ws) => {
      const rows: string[] = [];
      ws.eachRow({ includeEmpty: false }, (row) => {
        const values = (row.values as ExcelJS.CellValue[]).slice(1).map(cell);
        if (values.some((v) => v !== "")) rows.push(values.join(","));
      });
      return `--- Sheet: ${ws.name} ---\n${rows.join("\n")}`;
    })
    .join("\n\n");
}

/** Word headings, lists and tables as Markdown (so chunks keep heading paths); raw text if conversion yields nothing. */
async function docxText(buf: Buffer): Promise<string> {
  try {
    const md = htmlToMarkdown((await mammoth.convertToHtml({ buffer: buf })).value);
    if (md.trim()) return md;
  } catch {
    /* fall back to plain text */
  }
  return (await mammoth.extractRawText({ buffer: buf })).value;
}

export async function extractText(buf: Buffer, name: string): Promise<Extracted> {
  const ext = extOf(name);
  let out: Extracted;
  if (ext === "pdf") out = await pdfText(buf);
  else if (ext === "docx") out = { text: await docxText(buf) };
  else if (ext === "xlsx") out = { text: await sheetsText(buf) };
  else {
    if (buf.subarray(0, 4096).includes(0)) throw new Error("File looks binary, not text");
    out = { text: new TextDecoder("utf-8").decode(buf) };
  }
  return { ...out, text: out.text.replace(/\r\n/g, "\n").replace(/\u0000/g, "").slice(0, MAX_TEXT_CHARS) };
}
