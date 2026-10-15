/**
 * The sparky view of a Google Drive file: a summary with key points (documents) or a caption and the text read
 * from the picture (images), made by the same generator as stored files (aux model pool, same prompts), and
 * cached sealed with the owner's key per user + file. The cache entry carries Drive's modifiedTime, so an edited
 * file is read again. Drive files are not copied into sparky's storage: the text is fetched from Drive on demand.
 */
import { db } from "../../db/prisma.js";
import { userCrypto } from "../../crypto/userData.js";
import { toJpeg } from "../../files/media.js";
import { IMAGE_JPEG_QUALITY, IMAGE_MAX_EDGE } from "../../llm/vision.js";
import {
  defaultInsightDeps,
  IMAGE_PROMPT,
  SUMMARY_PROMPT,
  parseImageInsight,
  parseSummary,
  summaryInput,
  type FileInsight,
  type InsightDeps,
} from "../../files/insight.js";
import { AppError } from "../../util/errors.js";
import { log } from "../../util/logger.js";
import { USER_MSG } from "../../util/userMessages.js";
import { drive as liveDrive, MAX_DOWNLOAD_BYTES, type DriveFile } from "./drive.js";

export type DriveInsightPayload = {
  id: string;
  kind: "image" | "document" | "video" | "audio";
  status: "ready";
  chars: number;
  hasText: boolean;
  insight: FileInsight | null;
  video: null;
};

export type DriveText = { text: string; offset: number; truncated: boolean; chars: number };

/** Where sealed readings live: one entry per (user, file); a different modifiedTime is a miss. */
export type InsightCache = {
  get(userId: string, fileId: string): Promise<{ modifiedTime: string; sealed: string } | null>;
  put(userId: string, fileId: string, modifiedTime: string, sealed: string): Promise<void>;
};

export const dbInsightCache: InsightCache = {
  async get(userId, fileId) {
    const r = await db().driveInsight.findUnique({ where: { userId_fileId: { userId, fileId } }, select: { modifiedTime: true, sealed: true } });
    return r ?? null;
  },
  async put(userId, fileId, modifiedTime, sealed) {
    await db().driveInsight.upsert({
      where: { userId_fileId: { userId, fileId } },
      create: { userId, fileId, modifiedTime, sealed },
      update: { modifiedTime, sealed, createdAt: new Date() },
    });
  },
};

type Sealer = { seal(table: string, column: string, text: string): string; open(table: string, column: string, stored: string): string };
type Stored = { v: 1; insight: FileInsight; chars: number };

export type DriveInsightDeps = {
  drive: Pick<typeof liveDrive, "meta" | "read" | "stream">;
  cache: InsightCache;
  ai: Pick<InsightDeps, "chat" | "vision" | "now">;
  crypto: (userId: string) => Promise<Sealer>;
  /** Base64 JPEG of an image's bytes. */
  jpeg: (bytes: Buffer) => Promise<string>;
};

export const kindOf = (f: DriveFile): DriveInsightPayload["kind"] =>
  f.mimeType.startsWith("image/") ? "image" : f.mimeType.startsWith("video/") ? "video" : f.mimeType.startsWith("audio/") ? "audio" : "document";

/** The cache key part that changes when the file does. */
export const versionOf = (f: DriveFile) => f.modifiedTime ?? "unknown";

export function createDriveInsights(deps: DriveInsightDeps) {
  const running = new Map<string, Promise<Stored>>();

  async function cached(userId: string, f: DriveFile): Promise<Stored | null> {
    const hit = await deps.cache.get(userId, f.id).catch(() => null);
    if (!hit || hit.modifiedTime !== versionOf(f)) return null;
    try {
      const v = JSON.parse((await deps.crypto(userId)).open("drive", "insight", hit.sealed)) as Stored;
      return v?.v === 1 && typeof v.insight?.summary === "string" ? v : null;
    } catch {
      return null;
    }
  }

  const payload = (f: DriveFile, s: Stored | null): DriveInsightPayload => {
    const kind = kindOf(f);
    return { id: f.id, kind, status: "ready", chars: s?.chars ?? 0, hasText: kind === "image" || f.kind !== "none", insight: s?.insight ?? null, video: null };
  };

  /** What is stored; no model is called. */
  async function get(userId: string, id: string): Promise<DriveInsightPayload> {
    const f = await deps.drive.meta(userId, id);
    return payload(f, await cached(userId, f));
  }

  async function make(userId: string, f: DriveFile): Promise<Stored> {
    const at = deps.ai.now().toISOString();
    let insight: FileInsight;
    let chars = 0;
    try {
      if (kindOf(f) === "image") {
        if (f.size != null && f.size > MAX_DOWNLOAD_BYTES) throw new AppError(404, "not_found", USER_MSG.insightNoText);
        const s = await deps.drive.stream(userId, f.id);
        const image = await deps.jpeg(Buffer.from(await new Response(s.body).arrayBuffer()));
        const r = parseImageInsight(await deps.ai.vision([{ role: "user", content: IMAGE_PROMPT, images: [image] }]));
        if (!r) throw new AppError(503, "unavailable", USER_MSG.insightUnavailable, true);
        insight = { v: 1, summary: r.caption, keyPoints: r.keyPoints, caption: r.caption, ...(r.ocr ? { ocr: r.ocr } : {}), at };
        chars = r.ocr.length;
      } else {
        const c = await deps.drive.read(userId, f.id);
        if (c.format === "metadata" || !c.text.trim()) throw new AppError(404, "not_found", USER_MSG.insightNoText);
        chars = c.text.length;
        const r = parseSummary(
          await deps.ai.chat([
            { role: "system", content: SUMMARY_PROMPT },
            { role: "user", content: `File: ${f.name}\n\n${summaryInput(c.text)}` },
          ]),
        );
        if (!r) throw new AppError(503, "unavailable", USER_MSG.insightUnavailable, true);
        insight = { v: 1, ...r, at };
      }
    } catch (e) {
      if (e instanceof AppError) throw e;
      log.warn("drive insight failed", { kind: kindOf(f), message: (e as Error).message?.slice(0, 120) });
      throw new AppError(503, "unavailable", USER_MSG.insightUnavailable, true);
    }
    const stored: Stored = { v: 1, insight, chars };
    const sealed = (await deps.crypto(userId)).seal("drive", "insight", JSON.stringify(stored));
    await deps.cache.put(userId, f.id, versionOf(f), sealed).catch((e) => log.warn("drive insight not cached", { message: (e as Error).message?.slice(0, 120) }));
    return stored;
  }

  /** Reads the file once per version (`force` redoes it). Concurrent calls share one generation. */
  async function ensure(userId: string, id: string, opts: { force?: boolean } = {}): Promise<DriveInsightPayload> {
    const f = await deps.drive.meta(userId, id);
    if (!opts.force) {
      const hit = await cached(userId, f);
      if (hit) return payload(f, hit);
    }
    const key = `${userId}:${f.id}:${versionOf(f)}`;
    let p = running.get(key);
    if (!p) {
      p = make(userId, f).finally(() => running.delete(key));
      running.set(key, p);
    }
    return payload(f, await p);
  }

  /** The file's text (Docs as Markdown, Sheets as CSV, PDFs and Office extracted), paged in characters. */
  async function text(userId: string, id: string, offset = 0, limit = 200_000): Promise<DriveText> {
    const c = await deps.drive.read(userId, id);
    if (c.format === "metadata" || !c.text) throw new AppError(404, "not_found", "No text available");
    const lim = Math.min(Math.max(Math.floor(limit) || 200_000, 1), 1_000_000);
    const off = Math.max(Math.floor(offset) || 0, 0);
    return { text: c.text.slice(off, off + lim), offset: off, truncated: off + lim < c.text.length || c.truncated, chars: c.text.length };
  }

  return { get, ensure, text };
}

export const driveInsights = createDriveInsights({
  drive: liveDrive,
  cache: dbInsightCache,
  ai: defaultInsightDeps,
  crypto: (userId) => userCrypto(userId),
  jpeg: async (bytes) => (await toJpeg(bytes, IMAGE_MAX_EDGE, IMAGE_JPEG_QUALITY)).data.toString("base64"),
});
