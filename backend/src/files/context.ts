import { db } from "../db/prisma.js";
import { toVector } from "../db/vector.js";
import { ownerFilter } from "../auth/context.js";
import { embedTexts } from "../embeddings/index.js";
import { getObject } from "../storage/s3.js";
import type { ContextItem } from "../prompts/system.js";
import type { Message } from "../providers.js";
import { AppError } from "../util/errors.js";
import { CHUNK_THRESHOLD } from "./process.js";
import { toJpeg } from "./media.js";
import { INFO_SELECT, toFileRow, type FileRow } from "./store.js";

export const ATTACH_PLACEHOLDER = "(no message text, only attachments)";
const MAX_TRANSCRIPT_CHARS = 20_000;
const MAX_FULL_FOR_EVIDENCE = 150_000;

export type AttachedMessage = { role: "user" | "assistant"; content: string; attachments?: string[] };

export async function loadRows(ids: string[]): Promise<Map<string, FileRow>> {
  if (ids.length === 0) return new Map();
  // Another user's file id reads as not found.
  const [unscoped, uid] = ownerFilter();
  const rows = await db().storedFile.findMany({
    where: { id: { in: ids }, ...(unscoped ? {} : { userId: uid }) },
    select: INFO_SELECT,
  });
  const map = new Map(rows.map((r) => [r.id, toFileRow(r)]));
  const missing = ids.find((id) => !map.has(id));
  if (missing) throw new AppError(404, "not_found", `Attachment not found: ${missing}`);
  return map;
}

/** Polls until no listed file is processing. Returns the fresh rows. */
export async function waitForFiles(ids: string[], signal: AbortSignal, timeoutMs = 90_000): Promise<Map<string, FileRow>> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const rows = await loadRows(ids);
    const pending = [...rows.values()].some((r) => r.status === "processing");
    if (!pending || Date.now() >= deadline) {
      // Still processing after the deadline: treat as failed for this request.
      for (const r of rows.values()) if (r.status === "processing") (r.status = "failed", (r.error = "Still processing, try again shortly"));
      return rows;
    }
    if (signal.aborted) throw new DOMException("aborted", "AbortError");
    await new Promise((r) => setTimeout(r, 1000));
  }
}

const b64Cache = new Map<string, string[]>();
function remember(key: string, v: string[]) {
  b64Cache.set(key, v);
  if (b64Cache.size > 24) b64Cache.delete(b64Cache.keys().next().value!);
}

async function pixels(row: FileRow): Promise<string[]> {
  const hit = b64Cache.get(row.id);
  if (hit) return hit;
  let out: string[];
  if (row.kind === "image") {
    out = [(await toJpeg(await getObject(row.s3Key), 1280, 80)).data.toString("base64")];
  } else {
    const keys = (row.meta?.frameKeys as string[] | undefined) ?? [];
    out = await Promise.all(keys.map(async (k) => (await getObject(k)).toString("base64")));
  }
  remember(row.id, out);
  return out;
}

async function docText(id: string): Promise<string> {
  const row = await db().storedFile.findUnique({ where: { id }, select: { text: true } });
  return row?.text ?? "";
}

async function excerpt(row: FileRow, text: string, question: string, perDocChunks: number): Promise<string> {
  if (text.length <= CHUNK_THRESHOLD) return text;
  const head = () => text.slice(0, CHUNK_THRESHOLD);
  try {
    const has = await db().fileChunk.findFirst({ where: { fileId: row.id }, select: { id: true } });
    if (!has) return head();
    let chunks: Array<{ ord: number; content: string }>;
    if (question.trim()) {
      const [qv] = await embedTexts([question.slice(0, 2000)], "query");
      // Vector similarity stays raw SQL (pgvector operator).
      chunks = await db().$queryRaw<Array<{ ord: number; content: string }>>`
        SELECT ord, content FROM file_chunks WHERE file_id = ${row.id}::uuid
        ORDER BY embedding <=> ${toVector(qv)}::vector LIMIT ${perDocChunks}`;
    } else {
      chunks = await db().fileChunk.findMany({ where: { fileId: row.id }, orderBy: { ord: "asc" }, take: perDocChunks, select: { ord: true, content: true } });
    }
    chunks.sort((a, b) => a.ord - b.ord);
    return chunks.map((c) => c.content).join("\n[...]\n");
  } catch {
    return head();
  }
}

export type Prepared = {
  messages: Message[];
  docs: Array<ContextItem & { row: FileRow }>;
  failed: string[];
};

/** Turns request messages + resolved files into model messages (pixels, transcripts) and document context items. */
export async function prepareMessages(messages: AttachedMessage[], rows: Map<string, FileRow>, question: string): Promise<Prepared> {
  const hasPixels = (m: AttachedMessage) => m.role === "user" && (m.attachments ?? []).some((id) => ["image", "video"].includes(rows.get(id)?.kind ?? "") && rows.get(id)?.status === "ready");
  const withPixels = new Set(messages.map((m, i) => (hasPixels(m) ? i : -1)).filter((i) => i >= 0).slice(-2));

  const docRows: FileRow[] = [];
  const failed: string[] = [];
  const out: Message[] = [];

  for (const [i, m] of messages.entries()) {
    const ids = m.role === "user" ? [...new Set(m.attachments ?? [])] : [];
    if (ids.length === 0) {
      out.push({ role: m.role, content: m.content });
      continue;
    }
    const lines: string[] = [m.content.trim() || ATTACH_PLACEHOLDER];
    const images: string[] = [];
    for (const id of ids) {
      const r = rows.get(id)!;
      if (r.status !== "ready") {
        failed.push(r.name);
        lines.push(`[attachment "${r.name}" could not be processed: ${r.error ?? "unknown error"}]`);
        continue;
      }
      if (r.kind === "image") {
        if (withPixels.has(i)) {
          images.push(...(await pixels(r)));
          lines.push(`[attached image: ${r.name}]`);
        } else lines.push(`[image: ${r.name}]`);
      } else if (r.kind === "video") {
        const dur = r.meta?.durationS ? `, ${r.meta.durationS}s` : "";
        const frames = withPixels.has(i) ? await pixels(r) : [];
        images.push(...frames);
        lines.push(frames.length ? `[attached video: ${r.name}${dur}; ${frames.length} evenly spaced frames are attached as images]` : `[video: ${r.name}${dur}]`);
        const t = (await docText(r.id)).slice(0, MAX_TRANSCRIPT_CHARS);
        lines.push(t ? `Transcript of "${r.name}":\n${t}` : `(no speech detected in "${r.name}")`);
      } else if (r.kind === "audio") {
        const t = (await docText(r.id)).slice(0, MAX_TRANSCRIPT_CHARS);
        lines.push(t ? `[attached audio: ${r.name}${r.meta?.durationS ? `, ${r.meta.durationS}s` : ""}] Transcript:\n${t}` : `[audio: ${r.name}] (no speech detected)`);
      } else {
        if (!docRows.some((d) => d.id === r.id)) docRows.push(r);
        lines.push(`[attached document: ${r.name} = D${docRows.findIndex((d) => d.id === r.id) + 1}]`);
      }
    }
    out.push({ role: "user", content: lines.join("\n"), ...(images.length ? { images } : {}) });
  }

  const perDoc = Math.max(2, Math.floor(10 / Math.max(1, docRows.length)));
  const docs = await Promise.all(
    docRows.map(async (row, idx) => {
      const full = await docText(row.id);
      const text = await excerpt(row, full, question, perDoc);
      return { id: `D${idx + 1}`, title: row.name, url: `file:${row.id}`, heading: row.meta?.pages ? `${row.meta.pages} pages` : null, text, full: full.slice(0, MAX_FULL_FOR_EVIDENCE), row };
    }),
  );
  return { messages: out, docs, failed };
}
