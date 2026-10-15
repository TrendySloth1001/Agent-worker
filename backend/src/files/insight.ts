/**
 * "What sparky understands" about a file, for the preview's sparky view: a short summary with key points
 * (documents, audio, video), a caption and the text read from the picture (images). Generated on demand,
 * then cached on the file record, sealed with the owner's key like the extracted text.
 */
import { db } from "../db/prisma.js";
import { userCrypto } from "../crypto/userData.js";
import { ask } from "../llm/ask.js";
import { auxModels } from "../llm/auxPool.js";
import { pickVisionCandidates } from "../llm/router.js";
import { IMAGE_JPEG_QUALITY, IMAGE_MAX_EDGE, REASONING_VISION } from "../llm/vision.js";
import { withTelemetry } from "../db/usage.js";
import type { Message } from "../providers.js";
import { getUserObject } from "../storage/s3.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { toJpeg } from "./media.js";
import type { FileRow } from "./store.js";
import { USER_MSG } from "../util/userMessages.js";
import { ensureCaptions, evidenceFromMeta, defaultDescribe, fmtTs, readEvidence, writeEvidence, type Evidence, type VideoDeps } from "./video.js";

export const SUMMARY_PURPOSE = "file-summary";
export const IMAGE_PURPOSE = "file-insight";
/** How much of a document the summary model reads (head and tail of a long one). */
export const SUMMARY_INPUT_CHARS = 14_000;
const MAX_SUMMARY = 900;
const MAX_POINT = 240;
const MAX_POINTS = 7;
const MAX_OCR = 20_000;

export type FileInsight = { v: 1; summary: string; keyPoints: string[]; caption?: string; ocr?: string; at: string };

// ---- sealed cache on the file record ------------------------------------------------------------------

type RowLike = { id: string; userId?: string | null; meta?: Record<string, any> };

export async function readInsight(row: RowLike): Promise<FileInsight | null> {
  const sealed = row.meta?.insight;
  if (typeof sealed !== "string" || !sealed) return null;
  try {
    const v = JSON.parse((await userCrypto(row.userId ?? null)).open("files", "insight", sealed)) as FileInsight;
    return v?.v === 1 && typeof v.summary === "string" ? v : null;
  } catch {
    return null;
  }
}

export async function writeInsight(row: RowLike, insight: FileInsight): Promise<void> {
  const sealed = (await userCrypto(row.userId ?? null)).seal("files", "insight", JSON.stringify(insight));
  if (row.meta) row.meta.insight = sealed;
  // Raw: `meta || patch` merges JSON in the database without touching the other keys.
  await db().$executeRaw`UPDATE files SET meta = meta || ${JSON.stringify({ insight: sealed })}::jsonb WHERE id = ${row.id}::uuid`;
}

// ---- prompts and parsing -------------------------------------------------------------------------------

const LANGUAGE = "Write in the same language as the file's content.";

export const SUMMARY_PROMPT =
  `You read a file for the person who owns it. Reply with ONLY a JSON object: {"summary": string, "keyPoints": string[]}. ` +
  `"summary" is two to four plain sentences saying what the file is and what matters in it. "keyPoints" has 3 to ${MAX_POINTS} short bullet strings (facts, decisions, numbers, names, dates found in the file). ` +
  `Use only what the file says; never invent. ${LANGUAGE}`;

export const IMAGE_PROMPT =
  `Look at this image. Reply with ONLY a JSON object: {"caption": string, "text": string, "keyPoints": string[]}. ` +
  `"caption" is one or two plain sentences describing what is visible. "text" is all readable text in the image copied exactly, in reading order, or "" when there is none. ` +
  `"keyPoints" has up to 5 short strings for notable details (people doing what, objects, setting, numbers). Say "unclear" for what cannot be made out; do not guess names or brands. ${LANGUAGE}`;

const cut = (s: unknown, n: number) => (typeof s === "string" ? s.trim().slice(0, n) : "");

function jsonObject(raw: string): Record<string, unknown> | null {
  const clean = raw.replace(/<think>[\s\S]*?<\/think>/g, "");
  const a = clean.indexOf("{");
  const b = clean.lastIndexOf("}");
  if (a < 0 || b <= a) return null;
  try {
    const o = JSON.parse(clean.slice(a, b + 1)) as unknown;
    return o && typeof o === "object" && !Array.isArray(o) ? (o as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

const points = (v: unknown): string[] => (Array.isArray(v) ? v.map((x) => cut(x, MAX_POINT)).filter(Boolean).slice(0, MAX_POINTS) : []);

/** A summary + key points out of a model reply; plain prose is kept as the summary. Null when empty. */
export function parseSummary(raw: string): { summary: string; keyPoints: string[] } | null {
  const o = jsonObject(raw);
  if (o) {
    const summary = cut(o.summary, MAX_SUMMARY);
    return summary ? { summary, keyPoints: points(o.keyPoints) } : null;
  }
  const prose = raw.replace(/<think>[\s\S]*?<\/think>/g, "").trim();
  return prose ? { summary: prose.slice(0, MAX_SUMMARY), keyPoints: [] } : null;
}

/** A caption, the text in the picture and key points out of a vision reply. Null when nothing usable. */
export function parseImageInsight(raw: string): { caption: string; ocr: string; keyPoints: string[] } | null {
  const o = jsonObject(raw);
  if (o) {
    const caption = cut(o.caption, MAX_SUMMARY);
    const ocr = cut(o.text, MAX_OCR);
    return caption || ocr ? { caption, ocr, keyPoints: points(o.keyPoints) } : null;
  }
  const prose = raw.replace(/<think>[\s\S]*?<\/think>/g, "").trim();
  return prose ? { caption: prose.slice(0, MAX_SUMMARY), ocr: "", keyPoints: [] } : null;
}

/** Head and tail of a long text, so the summary sees how it starts and ends. */
export function summaryInput(text: string, max = SUMMARY_INPUT_CHARS): string {
  if (text.length <= max) return text;
  const head = Math.floor(max * 0.7);
  return `${text.slice(0, head)}\n\n[... middle of the file left out ...]\n\n${text.slice(text.length - (max - head))}`;
}

/** What a video's summary reads: described frames with their times, then the transcript. */
export function videoSource(ev: Evidence, transcript: string): string {
  const frames = ev.frames.filter((f) => f.caption).map((f) => `[${fmtTs(f.t)}] ${f.caption}`);
  const parts = [`Video, ${fmtTs(ev.durationS)} long.`];
  if (frames.length) parts.push(`What is on screen:\n${frames.join("\n")}`);
  if (transcript.trim()) parts.push(`What is said:\n${transcript.trim()}`);
  return parts.join("\n\n");
}

// ---- generation ----------------------------------------------------------------------------------------

export type InsightDeps = {
  /** One text completion (the small aux model pool). Throws when no model could answer. */
  chat(messages: Message[]): Promise<string>;
  /** One vision completion over a single image. Throws when no vision model could answer. */
  vision(messages: Message[]): Promise<string>;
  /** Base64 JPEG of an image file. */
  image(row: FileRow): Promise<string>;
  video: VideoDeps | ((row: FileRow) => VideoDeps);
  now(): Date;
};

const unavailable = () => new AppError(503, "unavailable", USER_MSG.insightUnavailable, true);

export const defaultInsightDeps: InsightDeps = {
  async chat(messages) {
    let last: unknown = null;
    for (const model of auxModels(1_800).slice(0, 3)) {
      try {
        const out = await ask(model, messages, { timeoutMs: 30_000, maxTokens: 700, temperature: 0.2, purpose: SUMMARY_PURPOSE });
        if (out.trim()) return out;
      } catch (e) {
        last = e;
        log.warn("file summary failed", { model, message: (e as Error).message?.slice(0, 120) });
      }
    }
    throw last ?? unavailable();
  },
  async vision(messages) {
    let last: unknown = null;
    for (const id of (await pickVisionCandidates()).filter((m) => !REASONING_VISION.test(m)).slice(0, 4)) {
      try {
        return await withTelemetry({ purpose: IMAGE_PURPOSE }, () => ask(id, messages, { timeoutMs: 40_000, maxTokens: 1_400, temperature: 0, purpose: IMAGE_PURPOSE }));
      } catch (e) {
        last = e;
      }
    }
    throw last ?? unavailable();
  },
  async image(row) {
    return (await toJpeg(await getUserObject(row.userId ?? null, row.s3Key), IMAGE_MAX_EDGE, IMAGE_JPEG_QUALITY)).data.toString("base64");
  },
  video: (row) => ({
    frame: async (k) => (await getUserObject(row.userId ?? null, k)).toString("base64"),
    describe: defaultDescribe,
    save: (e) => writeEvidence(row, e),
  }),
  now: () => new Date(),
};

/** The dependencies the routes use (tests swap them for fakes). */
export const insightIo: { deps: InsightDeps } = { deps: defaultInsightDeps };

const running = new Map<string, Promise<FileInsight>>();

/**
 * The cached insight of a ready file, or a freshly generated one (then cached). [text] is the extracted
 * text / transcript. Images use a vision model; everything else the small text models. Concurrent calls
 * for one file share one generation.
 */
export function ensureInsight(row: FileRow, text: string, deps: InsightDeps = defaultInsightDeps, opts: { force?: boolean } = {}): Promise<FileInsight> {
  const live = running.get(row.id);
  if (live) return live;
  const p = (async () => {
    if (!opts.force) {
      const hit = await readInsight(row);
      if (hit) return hit;
    }
    let insight: FileInsight;
    const at = deps.now().toISOString();
    try {
      if (row.kind === "image") {
        const image = await deps.image(row);
        const r = parseImageInsight(await deps.vision([{ role: "user", content: IMAGE_PROMPT, images: [image] }]));
        if (!r) throw unavailable();
        insight = { v: 1, summary: r.caption, keyPoints: r.keyPoints, caption: r.caption, ...(r.ocr ? { ocr: r.ocr } : {}), at };
      } else {
        let source = text;
        if (row.kind === "video") {
          const cached = await readEvidence(row);
          const ev0 = cached ?? evidenceFromMeta(row.meta, !!text);
          const vdeps = typeof deps.video === "function" ? deps.video(row) : deps.video;
          const keys = (row.meta?.frameKeys as string[] | undefined) ?? [];
          const ev = await ensureCaptions(row.id, keys, ev0, vdeps).catch(() => ev0);
          source = videoSource(ev, text);
        }
        if (!source.trim()) throw new AppError(404, "not_found", USER_MSG.insightNoText);
        const messages: Message[] = [
          { role: "system", content: SUMMARY_PROMPT },
          { role: "user", content: `File: ${row.name}\n\n${summaryInput(source)}` },
        ];
        const r = parseSummary(await deps.chat(messages));
        if (!r) throw unavailable();
        insight = { v: 1, ...r, at };
      }
    } catch (e) {
      if (e instanceof AppError) throw e;
      log.warn("file insight failed", { id: row.id, kind: row.kind, message: (e as Error).message?.slice(0, 120) });
      throw unavailable();
    }
    await writeInsight(row, insight);
    return insight;
  })().finally(() => running.delete(row.id));
  running.set(row.id, p);
  return p;
}

// ---- what the route returns ------------------------------------------------------------------------------

export type VideoTimeline = {
  durationS: number;
  frameStatus: Evidence["frameStatus"];
  captionStatus: Evidence["captionStatus"];
  transcriptStatus: Evidence["transcriptStatus"];
  frames: Array<{ t: number; caption?: string }>;
  segments: Array<{ start: number; end: number; text: string }>;
};

export type InsightPayload = {
  id: string;
  kind: FileRow["kind"];
  status: FileRow["status"];
  chars: number;
  hasText: boolean;
  insight: FileInsight | null;
  video: VideoTimeline | null;
};

/** The file's understanding as stored: no model is called. */
export async function insightPayload(row: FileRow, text: string): Promise<InsightPayload> {
  let video: VideoTimeline | null = null;
  if (row.kind === "video") {
    const ev = (await readEvidence(row)) ?? evidenceFromMeta(row.meta, !!text);
    video = {
      durationS: ev.durationS,
      frameStatus: ev.frameStatus,
      captionStatus: ev.captionStatus,
      transcriptStatus: ev.transcriptStatus,
      frames: ev.frames.map((f) => ({ t: f.t, ...(f.caption ? { caption: f.caption } : {}) })),
      segments: ev.segments.map((s) => ({ start: s.start, end: s.end, text: s.text })),
    };
  }
  return { id: row.id, kind: row.kind, status: row.status, chars: text.length, hasText: text.length > 0, insight: await readInsight(row), video };
}
