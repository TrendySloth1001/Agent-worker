import { writeFile } from "node:fs/promises";
import path from "node:path";
import pLimit from "p-limit";
import { db, Prisma } from "../db/prisma.js";
import { toVector } from "../db/vector.js";
import { embedTexts } from "../embeddings/index.js";
import { chunkMarkdown } from "../ingest/chunk.js";
import { getObject, putObject } from "../storage/s3.js";
import { log } from "../util/logger.js";
import { extractText } from "./extract.js";
import type { FileKind } from "./kinds.js";
import { extractFrames, imageSize, probe, toJpeg, transcribe, withTmp } from "./media.js";

const limit = pLimit(2);
export const CHUNK_THRESHOLD = 12_000;

type Target = { id: string; name: string; kind: FileKind; s3Key: string };

async function setResult(id: string, patch: { status: "ready" | "failed"; error?: string; thumbKey?: string | null; meta?: Record<string, unknown>; text?: string | null }) {
  // Raw: `meta || patch` merges JSON in the database (Prisma can only replace the whole value).
  await db().$executeRaw`
    UPDATE files SET status = ${patch.status}, error = ${patch.error ?? null}, thumb_key = COALESCE(${patch.thumbKey ?? null}, thumb_key),
      meta = meta || ${JSON.stringify(patch.meta ?? {})}::jsonb, text = COALESCE(${patch.text ?? null}, text)
    WHERE id = ${id}::uuid`;
}

async function processImage(t: Target, buf: Buffer) {
  const size = await imageSize(buf);
  const thumb = await toJpeg(buf, 512, 75);
  const thumbKey = `${t.id}/thumb.jpg`;
  await putObject(thumbKey, thumb.data, "image/jpeg");
  const dims = size ?? { width: thumb.width, height: thumb.height };
  await setResult(t.id, { status: "ready", thumbKey, meta: { width: dims.width, height: dims.height } });
}

async function processDocument(t: Target, buf: Buffer) {
  const { text, pages } = await extractText(buf, t.name);
  const meta: Record<string, unknown> = { chars: text.length, ...(pages ? { pages } : {}) };
  if (!text.trim()) {
    await setResult(t.id, { status: "failed", error: "No extractable text (scanned or empty document)", meta });
    return;
  }
  if (text.length > CHUNK_THRESHOLD) {
    try {
      const chunks = chunkMarkdown(text, t.name).slice(0, 400);
      const vectors = await embedTexts(chunks.map((c) => c.content), "document");
      await db().fileChunk.deleteMany({ where: { fileId: t.id } });
      // Vectors cannot go through createMany (Unsupported column): one multi-row INSERT per 50 chunks.
      for (let i = 0; i < chunks.length; i += 50) {
        const rows = chunks.slice(i, i + 50).map((c, j) => Prisma.sql`(${t.id}::uuid, ${c.ord}, ${c.content}, ${toVector(vectors[i + j])}::vector)`);
        await db().$executeRaw`INSERT INTO file_chunks (file_id, ord, content, embedding) VALUES ${Prisma.join(rows)}`;
      }
      meta.chunks = chunks.length;
    } catch (e) {
      // Retrieval falls back to the start of the document.
      meta.chunks = 0;
      log.warn("file embedding failed", { id: t.id, message: (e as Error).message.slice(0, 120) });
    }
  }
  await setResult(t.id, { status: "ready", meta, text });
}

async function processMedia(t: Target, buf: Buffer) {
  await withTmp(async (dir) => {
    const src = path.join(dir, `src${path.extname(t.name) || ".bin"}`);
    await writeFile(src, buf);
    const info = await probe(src);
    const meta: Record<string, unknown> = { durationS: Math.round(info.durationS * 10) / 10, hasAudio: info.hasAudio };
    let thumbKey: string | null = null;

    if (t.kind === "video") {
      if (info.width) Object.assign(meta, { width: info.width, height: info.height });
      const frames = info.hasVideo ? await extractFrames(src, dir, info.durationS) : [];
      const frameKeys: string[] = [];
      for (let i = 0; i < frames.length; i++) {
        const key = `${t.id}/frame-${i}.jpg`;
        await putObject(key, frames[i], "image/jpeg");
        frameKeys.push(key);
      }
      meta.frames = frameKeys.length;
      meta.frameKeys = frameKeys;
      if (frames.length > 0) {
        const poster = await toJpeg(frames[Math.floor(frames.length / 2)], 512, 75);
        thumbKey = `${t.id}/thumb.jpg`;
        await putObject(thumbKey, poster.data, "image/jpeg");
      }
    }

    let transcript = "";
    meta.hasTranscript = false;
    if (info.hasAudio) {
      try {
        transcript = await transcribe(src, dir, info.durationS);
        meta.hasTranscript = transcript.length > 0;
        if (info.durationS > 3600) meta.transcriptTruncated = true;
      } catch (e) {
        meta.transcriptError = (e as Error).message.slice(0, 160);
        log.warn("transcription failed", { id: t.id, message: (e as Error).message.slice(0, 120) });
        if (t.kind === "audio") {
          await setResult(t.id, { status: "failed", error: `Transcription failed: ${(e as Error).message.slice(0, 140)}`, meta });
          return;
        }
      }
    } else if (t.kind === "audio") {
      await setResult(t.id, { status: "failed", error: "No audio stream found", meta });
      return;
    }
    meta.chars = transcript.length;
    await setResult(t.id, { status: "ready", thumbKey, meta, text: transcript.slice(0, 400_000) });
  });
}

/** Runs after the upload response; always ends in ready or failed. */
export function processFile(t: Target, buf?: Buffer): Promise<void> {
  return limit(async () => {
    try {
      const data = buf ?? (await getObject(t.s3Key));
      if (t.kind === "image") await processImage(t, data);
      else if (t.kind === "document") await processDocument(t, data);
      else await processMedia(t, data);
    } catch (e) {
      log.warn("file processing failed", { id: t.id, message: (e as Error).message.slice(0, 160) });
      await setResult(t.id, { status: "failed", error: (e as Error).message.slice(0, 200) }).catch(() => {});
    }
  });
}

/** Files left in `processing` by a restart can never finish. */
export async function failInterrupted(): Promise<void> {
  try {
    await db().storedFile.updateMany({
      where: { status: "processing", createdAt: { lt: new Date(Date.now() - 10 * 60_000) } },
      data: { status: "failed", error: "Processing was interrupted" },
    });
  } catch {
    /* retried on the next start */
  }
}
