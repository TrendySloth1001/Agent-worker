import { createHash } from "node:crypto";

export type Chunk = { ord: number; headingPath: string | null; content: string; tokenCount: number; hash: string };

const TARGET = 500;
const HARD_MAX = 800;
const OVERLAP = 60;
const MIN = 40;

export const estTokens = (s: string) => Math.ceil(s.length / 4);
export const sha = (s: string) => createHash("sha256").update(s).digest("hex");

type Block = { text: string; kind: "fence" | "text" };
type Section = { path: string; blocks: Block[] };

function sectionize(md: string, docTitle: string | null): Section[] {
  const lines = md.replace(/\r\n/g, "\n").split("\n");
  const stack: Array<{ level: number; text: string }> = [];
  const sections: Section[] = [];
  let cur: Section = { path: docTitle ?? "", blocks: [] };
  let buf: string[] = [];
  let fence: string | null = null;

  const flush = (kind: "fence" | "text" = "text") => {
    const text = buf.join("\n").trim();
    buf = [];
    if (text) cur.blocks.push({ text, kind });
  };
  const pathOf = () => [docTitle, ...stack.map((s) => s.text)].filter(Boolean).filter((v, i, a) => a.indexOf(v) === i).join(" > ");

  for (const line of lines) {
    if (fence) {
      buf.push(line);
      if (line.trim().startsWith(fence)) {
        fence = null;
        flush("fence");
      }
      continue;
    }
    const fm = line.match(/^\s*(```+|~~~+)/);
    if (fm) {
      flush();
      fence = fm[1];
      buf.push(line);
      continue;
    }
    const hm = line.match(/^(#{1,6})\s+(.+?)\s*#*$/);
    if (hm) {
      flush();
      const level = hm[1].length;
      while (stack.length && stack[stack.length - 1].level >= level) stack.pop();
      stack.push({ level, text: hm[2].replace(/\[([^\]]*)\]\([^)]*\)/g, "$1").replace(/[*_`]/g, "").replace(/\s*\{#[^}]*\}\s*$/, "").trim() });
      if (cur.blocks.length) sections.push(cur);
      cur = { path: pathOf(), blocks: [] };
      continue;
    }
    if (line.trim() === "") {
      flush();
      continue;
    }
    buf.push(line);
  }
  flush(fence ? "fence" : "text");
  if (cur.blocks.length) sections.push(cur);
  return sections;
}

function splitLarge(b: Block): Block[] {
  if (estTokens(b.text) <= HARD_MAX) return [b];
  const maxChars = HARD_MAX * 4 - 200;
  const out: Block[] = [];
  if (b.kind === "fence") {
    const lines = b.text.split("\n");
    const open = lines[0];
    const hasClose = lines.length > 1 && /^\s*(```+|~~~+)\s*$/.test(lines[lines.length - 1]);
    const close = hasClose ? lines[lines.length - 1] : open.match(/^\s*(```+|~~~+)/)![1];
    const body = lines.slice(1, hasClose ? -1 : undefined);
    let cur: string[] = [];
    let len = 0;
    for (const l of body) {
      if (len + l.length + 1 > maxChars && cur.length) {
        out.push({ kind: "fence", text: [open, ...cur, close].join("\n") });
        cur = [];
        len = 0;
      }
      // a single enormous line (minified): hard cut
      if (l.length > maxChars) {
        for (let i = 0; i < l.length; i += maxChars) out.push({ kind: "fence", text: [open, l.slice(i, i + maxChars), close].join("\n") });
        continue;
      }
      cur.push(l);
      len += l.length + 1;
    }
    if (cur.length) out.push({ kind: "fence", text: [open, ...cur, close].join("\n") });
    return out;
  }
  const parts = b.text.split(/(?<=[.!?])\s+|\n/);
  let cur = "";
  for (const p of parts) {
    if (cur && cur.length + p.length + 1 > maxChars) {
      out.push({ kind: "text", text: cur });
      cur = "";
    }
    if (p.length > maxChars) {
      for (let i = 0; i < p.length; i += maxChars) out.push({ kind: "text", text: p.slice(i, i + maxChars) });
      continue;
    }
    cur = cur ? `${cur} ${p}` : p;
  }
  if (cur) out.push({ kind: "text", text: cur });
  return out;
}

/** Markdown-aware chunker. Embedded text for a chunk should be `headingPath + "\n" + content`. */
export function chunkMarkdown(md: string, docTitle: string | null): Chunk[] {
  const raw: Array<{ path: string; text: string; lastKind: string }> = [];
  for (const sec of sectionize(md, docTitle)) {
    let cur: string[] = [];
    let tokens = 0;
    let lastKind = "text";
    let prevTail = "";
    const emit = () => {
      if (!cur.length) return;
      const body = cur.join("\n\n");
      raw.push({ path: sec.path, text: prevTail ? `${prevTail}\n\n${body}` : body, lastKind });
      prevTail = lastKind === "fence" ? "" : body.slice(-OVERLAP * 4).replace(/^\S*\s/, "");
      cur = [];
      tokens = 0;
    };
    for (const b0 of sec.blocks) {
      for (const b of splitLarge(b0)) {
        const t = estTokens(b.text);
        if (cur.length && tokens + t > TARGET) emit();
        cur.push(b.text);
        tokens += t;
        lastKind = b.kind;
        if (tokens >= TARGET) emit();
      }
    }
    emit();
  }

  // merge tiny chunks into a neighbour with the same heading path
  const merged: typeof raw = [];
  for (const c of raw) {
    const prev = merged[merged.length - 1];
    if (prev && estTokens(c.text) < MIN && prev.path === c.path && estTokens(prev.text) + estTokens(c.text) <= HARD_MAX) {
      prev.text += `\n\n${c.text}`;
    } else if (prev && estTokens(prev.text) < MIN && prev.path === c.path && estTokens(prev.text) + estTokens(c.text) <= HARD_MAX) {
      prev.text += `\n\n${c.text}`;
    } else merged.push({ ...c });
  }
  return merged
    .filter((c) => c.text.trim().length > 0)
    .map((c, i) => ({
      ord: i,
      headingPath: c.path || null,
      content: c.text.trim(),
      tokenCount: estTokens(c.text),
      hash: sha(`${c.path}\n${c.text}`),
    }));
}

export function embeddingInput(c: { headingPath: string | null; content: string }): string {
  return c.headingPath ? `${c.headingPath}\n${c.content}` : c.content;
}
