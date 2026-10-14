/**
 * Grounded video answers. A video reaches the model as an "evidence pack":
 * timestamped keyframes (and short descriptions of each, written by a vision
 * model), the timestamped transcript, and the facts (length, size). The pack
 * is built once, cached sealed on the file record, and every answer is told
 * to rely on nothing else.
 */
import { db } from "../db/prisma.js";
import { userCrypto } from "../crypto/userData.js";
import { ask } from "../llm/ask.js";
import { pickVisionCandidates } from "../llm/router.js";
import { REASONING_VISION } from "../llm/vision.js";
import { withTelemetry } from "../db/usage.js";
import type { Message } from "../providers.js";
import { log } from "../util/logger.js";
import type { TimedSegment } from "./media.js";

// ---- frame selection ---------------------------------------------------------------------------

export const MAX_FRAMES = 12;
export const MIN_FRAMES = 3;
const SECONDS_PER_FRAME = 5;
/** Longer videos are not described frame by frame (too sparse to be trusted). */
export const MAX_ANALYZE_S = 30 * 60;
/** Frames attached to one answer call (Groq accepts 5 images per request). */
export const MAX_FRAMES_TO_MODEL = 5;
/** Frames described per vision call (each image costs about 1.8k tokens of the per-minute budget). */
const CAPTION_BATCH = 3;
const MAX_CAPTION_CHARS = 320;
const MAX_STORED_TRANSCRIPT_CHARS = 40_000;
const MAX_PROMPT_TRANSCRIPT_CHARS = 20_000;

/**
 * Seconds at which to grab frames: one per ~5 s, at least 3 (a single one for
 * clips under 2 s), at most 12, each in the middle of its equal slice so the
 * first and last frames are not black fades.
 */
export function planFrames(durationS: number): number[] {
  if (!(durationS > 0)) return [0];
  if (durationS < 2) return [Math.round(durationS * 50) / 100];
  const n = Math.min(MAX_FRAMES, Math.max(MIN_FRAMES, Math.ceil(durationS / SECONDS_PER_FRAME)));
  return Array.from({ length: n }, (_, i) => Math.round(((durationS * (i + 0.5)) / n) * 100) / 100);
}

/** Frames stored before timestamps were kept were evenly spaced mid-slice: the same times can be recomputed. */
export function legacyFrameTimes(count: number, durationS: number): number[] {
  return Array.from({ length: count }, (_, i) => Math.round(((durationS * (i + 0.5)) / Math.max(1, count)) * 100) / 100);
}

/** 0:42, 12:05, 1:02:03 */
export function fmtTs(s: number): string {
  const t = Math.max(0, Math.floor(s));
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const sec = String(t % 60).padStart(2, "0");
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${sec}` : `${m}:${sec}`;
}

/** Evenly spread picks from [0, total): the frames that go to the model together with the answer. */
export function pickEvenly(total: number, max: number): number[] {
  if (total <= max) return Array.from({ length: total }, (_, i) => i);
  return Array.from({ length: max }, (_, i) => Math.floor(((i + 0.5) * total) / max));
}

// ---- evidence pack ------------------------------------------------------------------------------

export type EvidenceFrame = { t: number; caption?: string };
export type Evidence = {
  v: 1;
  durationS: number;
  width: number;
  height: number;
  hasAudio: boolean;
  /** none: no frame could be extracted; ok: frames exist. */
  frameStatus: "ok" | "none";
  tooLong: boolean;
  frames: EvidenceFrame[];
  /** pending: not described yet; ok: every frame; partial: some; failed: none could be described. */
  captionStatus: "pending" | "ok" | "partial" | "failed";
  transcriptStatus: "ok" | "silent" | "failed" | "no_audio";
  segments: TimedSegment[];
};

/** Joins Whisper's short segments into lines of at least ~10 s so the pack stays small. */
export function mergeSegments(segs: TimedSegment[], minSpanS = 10): TimedSegment[] {
  const out: TimedSegment[] = [];
  for (const s of segs) {
    const last = out[out.length - 1];
    if (last && last.end - last.start < minSpanS) {
      last.end = s.end;
      last.text = `${last.text} ${s.text}`;
    } else out.push({ ...s });
  }
  let chars = 0;
  return out.filter((s) => (chars += s.text.length) <= MAX_STORED_TRANSCRIPT_CHARS);
}

export function baseEvidence(i: {
  durationS: number;
  width?: number;
  height?: number;
  hasAudio: boolean;
  frameTimes: number[];
  segments?: TimedSegment[];
  hasTranscript: boolean;
  transcriptFailed?: boolean;
}): Evidence {
  const tooLong = i.durationS > MAX_ANALYZE_S;
  return {
    v: 1,
    durationS: i.durationS,
    width: i.width ?? 0,
    height: i.height ?? 0,
    hasAudio: i.hasAudio,
    frameStatus: i.frameTimes.length > 0 ? "ok" : "none",
    tooLong,
    frames: i.frameTimes.map((t) => ({ t })),
    captionStatus: i.frameTimes.length === 0 || tooLong ? "failed" : "pending",
    transcriptStatus: !i.hasAudio ? "no_audio" : i.transcriptFailed ? "failed" : i.hasTranscript ? "ok" : "silent",
    segments: mergeSegments(i.segments ?? []),
  };
}

type RowLike = { id: string; userId?: string | null; meta?: Record<string, any> };

const sealPack = async (userId: string | null | undefined, ev: Evidence) => (await userCrypto(userId ?? null)).seal("files", "evidence", JSON.stringify(ev));

/** Sealed pack for processing to put in the file's meta. */
export const sealEvidence = sealPack;

export async function readEvidence(row: RowLike): Promise<Evidence | null> {
  const sealed = row.meta?.evidence;
  if (typeof sealed !== "string" || !sealed) return null;
  try {
    const ev = JSON.parse((await userCrypto(row.userId ?? null)).open("files", "evidence", sealed)) as Evidence;
    return ev?.v === 1 && Array.isArray(ev.frames) ? ev : null;
  } catch {
    return null;
  }
}

export async function writeEvidence(row: RowLike, ev: Evidence): Promise<void> {
  const sealed = await sealPack(row.userId, ev);
  if (row.meta) row.meta.evidence = sealed;
  // Raw: `meta || patch` merges JSON in the database without touching the other keys.
  await db().$executeRaw`UPDATE files SET meta = meta || ${JSON.stringify({ evidence: sealed })}::jsonb WHERE id = ${row.id}::uuid`;
}

/** The pack for a file processed before packs existed: facts and frame times from its meta, no captions yet. */
export function evidenceFromMeta(meta: Record<string, any>, hasTranscript: boolean): Evidence {
  const durationS = Number(meta.durationS) || 0;
  const frameCount = Array.isArray(meta.frameKeys) ? meta.frameKeys.length : 0;
  const times = Array.isArray(meta.frameTimes) && meta.frameTimes.length === frameCount ? (meta.frameTimes as number[]) : legacyFrameTimes(frameCount, durationS);
  return baseEvidence({
    durationS,
    width: Number(meta.width) || 0,
    height: Number(meta.height) || 0,
    hasAudio: !!meta.hasAudio,
    frameTimes: times,
    hasTranscript,
    transcriptFailed: !!meta.transcriptError,
  });
}

// ---- frame descriptions -------------------------------------------------------------------------

export const CAPTION_PROMPT = (times: number[]) =>
  `These ${times.length} images are frames from one video, in order, at ${times.map((t) => `[${fmtTs(t)}]`).join(", ")}.
Describe each frame in one or two plain sentences: only what is visible (people and what they do, objects, setting, text on screen copied exactly). Do not guess names, brands or events you cannot see, and say nothing about what happens before or after the frame. If something cannot be made out, write "unclear" for that part.
Reply with ONLY a JSON array of ${times.length} strings, one per frame, in the same order.`;

/** Descriptions out of a model reply: a JSON array of exactly [n] strings, else null. */
export function parseCaptions(raw: string, n: number): string[] | null {
  const a = raw.indexOf("[");
  const b = raw.lastIndexOf("]");
  if (a < 0 || b <= a) return null;
  try {
    const arr = JSON.parse(raw.slice(a, b + 1)) as unknown;
    if (!Array.isArray(arr) || arr.length !== n) return null;
    const out = arr.map((x) => (typeof x === "string" ? x.trim().slice(0, MAX_CAPTION_CHARS) : ""));
    return out.every(Boolean) ? out : null;
  } catch {
    return null;
  }
}

export type VideoDeps = {
  /** Base64 JPEG of the frame at [key]. */
  frame(key: string): Promise<string>;
  /** One vision call over [messages]; throws when no vision model could answer. */
  describe(messages: Message[], signal?: AbortSignal): Promise<string>;
  save(ev: Evidence): Promise<void>;
};

const ONE_IMAGE = /llama-3\.2-\d+b-vision/;

/** Vision models that take several images per call and answer quickly (not the one-image or reasoning ones). */
export async function captionModels(): Promise<string[]> {
  return (await pickVisionCandidates()).filter((id) => !ONE_IMAGE.test(id) && !REASONING_VISION.test(id));
}

export const defaultDescribe: VideoDeps["describe"] = async (messages, signal) => {
  let last: unknown = new Error("no vision model available");
  for (const id of await captionModels()) {
    if (signal?.aborted) throw new DOMException("aborted", "AbortError");
    try {
      return await withTelemetry({ purpose: "video-caption" }, () => ask(id, messages, { timeoutMs: 45_000, maxTokens: 900, temperature: 0, purpose: "video-caption", signal }));
    } catch (e) {
      last = e;
    }
  }
  throw last;
};

const inflight = new Map<string, Promise<Evidence>>();

/**
 * Describes the frames that have no description yet, three per vision call, and caches the result.
 * Never throws: a failure leaves the pack marked failed/partial and the answer says so.
 */
export async function ensureCaptions(fileId: string, frameKeys: string[], ev: Evidence, deps: VideoDeps, signal?: AbortSignal): Promise<Evidence> {
  if (ev.frameStatus !== "ok" || ev.tooLong || ev.frames.every((f) => f.caption) || frameKeys.length !== ev.frames.length) return ev;
  const running = inflight.get(fileId);
  if (running) return running;
  const p = (async () => {
    const next: Evidence = { ...ev, frames: ev.frames.map((f) => ({ ...f })) };
    for (let i = 0; i < next.frames.length; i += CAPTION_BATCH) {
      if (signal?.aborted) break;
      const idx = next.frames.slice(i, i + CAPTION_BATCH).map((_, k) => i + k).filter((k) => !next.frames[k].caption);
      if (idx.length === 0) continue;
      try {
        const images = await Promise.all(idx.map((k) => deps.frame(frameKeys[k])));
        const raw = await deps.describe([{ role: "user", content: CAPTION_PROMPT(idx.map((k) => next.frames[k].t)), images }], signal);
        const caps = parseCaptions(raw.replace(/<think>[\s\S]*?<\/think>/g, ""), idx.length);
        if (caps) idx.forEach((k, j) => (next.frames[k].caption = caps[j]));
      } catch (e) {
        log.warn("video frame description failed", { id: fileId, message: (e as Error).message?.slice(0, 120) });
      }
    }
    const done = next.frames.filter((f) => f.caption).length;
    next.captionStatus = done === next.frames.length ? "ok" : done > 0 ? "partial" : "failed";
    // An aborted request leaves the pack as it was so the next one retries.
    if (!signal?.aborted || done > 0) await deps.save(next).catch((e) => log.warn("evidence save failed", { id: fileId, message: (e as Error).message?.slice(0, 120) }));
    return next;
  })().finally(() => inflight.delete(fileId));
  inflight.set(fileId, p);
  return p;
}

// ---- what the model is told -----------------------------------------------------------------------

export const GROUNDING_NOTE =
  "Video rules: answer only from the frames, frame descriptions and transcript given for the video. Cite moments like [0:42]. Say plainly what cannot be determined from them (for example what happens between frames, or anything not shown or said). Never invent events, people, text or details that are not in them; write \"unclear\" when unsure.";

/** Said instead of the usual image fallback when the frames could not be shown to a model. */
export const VIDEO_TEXT_ONLY_NOTE =
  "The user attached a video, but no model that can see images was available. Answer only from the frame descriptions and transcript in the message, cite timestamps like [0:42], and say plainly that you could not look at the video frames yourself. Never invent what the video shows.";

/** Questions about speech, topic or a summary can be answered from the pack; the rest need to see the frames. */
const AUDIO_ONLY_RE = /\b(transcri\w*|what (did|does|do) (he|she|they|the \w+|i|we|you) (say|said|mention\w*|talk\w*)|says?|said|speech|spoken|words?|lyrics|subtitles?|captions?|audio|voice|translate|language)\b/i;
const VISUAL_RE = /\b(see|seen|show\w*|look\w*|visible|wear\w*|color|colour|who|where|scene|screen|appear\w*|happen\w*|doing|holding|background|people|person|object|frame|shot|image|picture|text on)\b/i;

/** Whether an answer should get the actual frames. Unclear questions get them: it is the safer side. */
export function needsFrames(question: string): boolean {
  const q = question.trim();
  if (!q) return true;
  if (VISUAL_RE.test(q)) return true;
  return !AUDIO_ONLY_RE.test(q);
}

export type VideoRoute = { sendFrames: boolean; frameIdx: number[]; notices: string[] };

/**
 * Which frames go to the model with this question. Frames are sent when the
 * question is visual and there are frames to show; otherwise the pack's text
 * answers. Also lists what a user should be told about limits.
 */
export function routeVideo(ev: Evidence, question: string): VideoRoute {
  const notices: string[] = [];
  if (ev.frameStatus === "none") notices.push("Couldn't pull pictures out of that video, so I can only go by what's said in it.");
  else if (ev.tooLong) notices.push("That video is too long for me to look through closely, so I can only go by what's said in it.");
  else if (ev.captionStatus === "failed") notices.push("Couldn't look closely at that video just now, so my answer may be thin on what it shows.");
  const canShow = ev.frameStatus === "ok" && !ev.tooLong;
  const sendFrames = canShow && needsFrames(question);
  return { sendFrames, frameIdx: sendFrames ? pickEvenly(ev.frames.length, MAX_FRAMES_TO_MODEL) : [], notices };
}

const dims = (ev: Evidence) => (ev.width && ev.height ? `, ${ev.width}x${ev.height}` : "");

/** The text block that stands for a video in the user's message. */
export function renderVideoBlock(name: string, ev: Evidence, route: VideoRoute, transcriptFallback = ""): string {
  const lines: string[] = [`[attached video: ${name}, ${fmtTs(ev.durationS)} long${dims(ev)}]`];
  if (ev.frameStatus === "none") lines.push("Frames: none could be extracted, so nothing is known about what the video shows.");
  else if (ev.tooLong) lines.push(`Frames: not examined, the video is too long (${fmtTs(ev.durationS)}). Nothing is known about what it shows.`);
  else {
    lines.push(`Frames: ${ev.frames.length} sampled, at ${ev.frames.map((f) => `[${fmtTs(f.t)}]`).join(" ")}. Nothing is known about the moments between them.`);
    if (ev.captionStatus === "ok" || ev.captionStatus === "partial") {
      lines.push("Frame descriptions (written by an image model; \"unclear\" means it could not tell):");
      for (const f of ev.frames) lines.push(f.caption ? `[${fmtTs(f.t)}] ${f.caption}` : `[${fmtTs(f.t)}] (not described)`);
    } else if (!route.sendFrames) lines.push("Frame descriptions: unavailable, so what the video shows is unknown.");
    if (route.sendFrames) lines.push(`Attached images, in order, are the frames at ${route.frameIdx.map((i) => `[${fmtTs(ev.frames[i].t)}]`).join(" ")}. If fewer images arrive, use the descriptions.`);
  }
  if (ev.transcriptStatus === "no_audio") lines.push("Transcript: the video has no audio track.");
  else if (ev.transcriptStatus === "failed") lines.push("Transcript: could not be made, so what is said is unknown.");
  else if (ev.transcriptStatus === "silent") lines.push("Transcript: no speech detected.");
  else if (ev.segments.length > 0) {
    let used = 0;
    const out: string[] = [];
    for (const s of ev.segments) {
      if ((used += s.text.length) > MAX_PROMPT_TRANSCRIPT_CHARS) {
        out.push("(transcript cut short here)");
        break;
      }
      out.push(`[${fmtTs(s.start)}] ${s.text}`);
    }
    lines.push("Transcript (timestamps are approximate):", ...out);
  } else if (transcriptFallback) lines.push("Transcript (no timestamps available):", transcriptFallback.slice(0, MAX_PROMPT_TRANSCRIPT_CHARS));
  else lines.push("Transcript: no speech detected.");
  return lines.join("\n");
}
