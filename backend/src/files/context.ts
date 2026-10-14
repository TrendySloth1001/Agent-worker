import { db } from "../db/prisma.js";
import { toVector } from "../db/vector.js";
import { ownerFilter } from "../auth/context.js";
import { embedTexts } from "../embeddings/index.js";
import { getUserObject } from "../storage/s3.js";
import { userCrypto } from "../crypto/userData.js";
import type { ContextItem } from "../prompts/system.js";
import type { Message } from "../providers.js";
import { AppError } from "../util/errors.js";
import { CHUNK_THRESHOLD } from "./process.js";
import { toJpeg } from "./media.js";
import { IMAGE_JPEG_QUALITY, IMAGE_MAX_EDGE } from "../llm/vision.js";
import { INFO_SELECT, toFileRow, type FileRow } from "./store.js";
import { defaultDescribe, ensureCaptions, evidenceFromMeta, GROUNDING_NOTE, readEvidence, renderVideoBlock, routeVideo, writeEvidence, type Evidence, type VideoDeps } from "./video.js";

export const ATTACH_PLACEHOLDER = "(no message text, only attachments)";
const MAX_TRANSCRIPT_CHARS = 20_000;
const MAX_FULL_FOR_EVIDENCE = 150_000;

export type AttachedMessage = { role: "user" | "assistant"; content: string; attachments?: string[] };

/**
 * The caller's files by id. Ids in [required] must exist (404 otherwise);
 * others may be missing (deleted from storage) and are left out of the map.
 */
export async function loadRows(ids: string[], required: string[] = ids): Promise<Map<string, FileRow>> {
  if (ids.length === 0) return new Map();
  // Another user's file id reads as not found.
  const [unscoped, uid] = ownerFilter();
  const rows = await db().storedFile.findMany({
    where: { id: { in: ids }, ...(unscoped ? {} : { userId: uid }) },
    select: INFO_SELECT,
  });
  const map = new Map(rows.map((r) => [r.id, toFileRow(r)]));
  const missing = required.find((id) => !map.has(id));
  if (missing) throw new AppError(404, "not_found", `Attachment not found: ${missing}`);
  return map;
}

/** Polls until no listed file is processing. Returns the fresh rows. */
export async function waitForFiles(ids: string[], signal: AbortSignal, timeoutMs = 90_000, required: string[] = ids): Promise<Map<string, FileRow>> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const rows = await loadRows(ids, required);
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
/** The cache is bounded by memory (base64 characters), not just by entry count. */
const B64_CACHE_MAX_BYTES = 32 * 1024 * 1024;
const B64_CACHE_MAX_ENTRIES = 24;
let b64Bytes = 0;
const sizeOf = (v: string[]) => v.reduce((n, s) => n + s.length, 0);
function remember(key: string, v: string[]) {
  const size = sizeOf(v);
  if (size > B64_CACHE_MAX_BYTES) return; // too big to keep at all
  const old = b64Cache.get(key);
  if (old) {
    b64Bytes -= sizeOf(old);
    b64Cache.delete(key);
  }
  b64Cache.set(key, v);
  b64Bytes += size;
  while (b64Cache.size > B64_CACHE_MAX_ENTRIES || b64Bytes > B64_CACHE_MAX_BYTES) {
    const oldest = b64Cache.keys().next().value!;
    b64Bytes -= sizeOf(b64Cache.get(oldest)!);
    b64Cache.delete(oldest);
  }
}

async function pixels(row: FileRow): Promise<string[]> {
  const hit = b64Cache.get(row.id);
  if (hit) return hit;
  let out: string[];
  if (row.kind === "image") {
    out = [(await toJpeg(await getUserObject(row.userId ?? null, row.s3Key), IMAGE_MAX_EDGE, IMAGE_JPEG_QUALITY)).data.toString("base64")];
  } else {
    const keys = (row.meta?.frameKeys as string[] | undefined) ?? [];
    out = await Promise.all(keys.map(async (k) => (await getUserObject(row.userId ?? null, k)).toString("base64")));
  }
  remember(row.id, out);
  return out;
}

async function docText(id: string): Promise<string> {
  const row = await db().storedFile.findUnique({ where: { id }, select: { text: true, userId: true } });
  return row?.text ? (await userCrypto(row.userId)).open("files", "text", row.text) : "";
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
    const crypto = await userCrypto(row.userId ?? null);
    return chunks.map((c) => crypto.open("file_chunks", "content", c.content)).join("\n[...]\n");
  } catch {
    return head();
  }
}

export type Prepared = {
  messages: Message[];
  docs: Array<ContextItem & { row: FileRow }>;
  failed: string[];
  /** User-safe notes about what could not be read from videos (shown as a notice). */
  videoNotices: string[];
};

export type PrepareOptions = { signal?: AbortSignal; deps?: Partial<VideoDeps> };

/** The pack of a ready video: cached, or built from its facts; frames are described only for the newest message's videos. */
async function videoEvidence(row: FileRow, describe: boolean, opts: PrepareOptions): Promise<Evidence> {
  const cached = await readEvidence(row);
  const ev = cached ?? evidenceFromMeta(row.meta, !!(await docText(row.id)));
  if (!describe) return ev;
  const keys = (row.meta?.frameKeys as string[] | undefined) ?? [];
  const deps: VideoDeps = {
    frame: opts.deps?.frame ?? (async (k) => (await getUserObject(row.userId ?? null, k)).toString("base64")),
    describe: opts.deps?.describe ?? defaultDescribe,
    save: opts.deps?.save ?? ((e) => writeEvidence(row, e)),
  };
  return ensureCaptions(row.id, keys, ev, deps, opts.signal);
}

/** Turns request messages + resolved files into model messages (pixels, transcripts) and document context items. */
export async function prepareMessages(messages: AttachedMessage[], rows: Map<string, FileRow>, question: string, opts: PrepareOptions = {}): Promise<Prepared> {
  const hasPixels = (m: AttachedMessage) => m.role === "user" && (m.attachments ?? []).some((id) => ["image", "video"].includes(rows.get(id)?.kind ?? "") && rows.get(id)?.status === "ready");
  const withPixels = new Set(messages.map((m, i) => (hasPixels(m) ? i : -1)).filter((i) => i >= 0).slice(-2));
  const lastUserIdx = messages.map((m) => m.role === "user").lastIndexOf(true);
  const videoQuestion = ([...messages].reverse().find((m) => m.role === "user")?.content ?? question).replace(ATTACH_PLACEHOLDER, "");
  const videoNotices: string[] = [];

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
      const r = rows.get(id);
      if (!r) {
        lines.push("[an earlier attachment was deleted by the user and is no longer available]");
        continue;
      }
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
        const ev = await videoEvidence(r, i === lastUserIdx || withPixels.has(i), opts);
        // Frames go along only in the newest messages and only when the question is about what is shown.
        const route = routeVideo(ev, videoQuestion);
        const frames = withPixels.has(i) && route.sendFrames ? await pixels(r) : [];
        const shown = frames.length > 0 && frames.length === ev.frames.length ? route.frameIdx.map((k) => frames[k]) : [];
        const sent = shown.length > 0 ? route : { ...route, sendFrames: false, frameIdx: [] };
        images.push(...shown);
        lines.push(renderVideoBlock(r.name, ev, sent, sent.sendFrames ? "" : await docText(r.id)));
        if (!lines.includes(GROUNDING_NOTE)) lines.push(GROUNDING_NOTE);
        if (withPixels.has(i)) videoNotices.push(...route.notices);
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
  return { messages: out, docs, failed, videoNotices: [...new Set(videoNotices)] };
}
