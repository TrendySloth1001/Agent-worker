import { spawn } from "node:child_process";
import { mkdtemp, rm, writeFile, readFile, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import sharp from "sharp";
import { config } from "../config.js";
import { recordUsage } from "../db/usage.js";

const FFMPEG = process.env.FFMPEG_PATH || (process.platform === "darwin" ? "/opt/homebrew/bin/ffmpeg" : "ffmpeg");
const FFPROBE = process.env.FFPROBE_PATH || (process.platform === "darwin" ? "/opt/homebrew/bin/ffprobe" : "ffprobe");

function run(cmd: string, args: string[], timeoutMs = 120_000): Promise<{ stdout: string; code: number }> {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => p.kill("SIGKILL"), timeoutMs);
    p.stdout.on("data", (d) => (stdout += d));
    p.stderr.on("data", (d) => (stderr = (stderr + d).slice(-2000)));
    p.on("error", (e) => (clearTimeout(timer), reject(e)));
    p.on("close", (code) => {
      clearTimeout(timer);
      if (code === 0) resolve({ stdout, code });
      else reject(new Error(`${path.basename(cmd)} exited ${code}: ${stderr.trim().split("\n").slice(-2).join(" ").slice(0, 200)}`));
    });
  });
}

export async function withTmp<T>(fn: (dir: string) => Promise<T>): Promise<T> {
  const dir = await mkdtemp(path.join(tmpdir(), "att-"));
  try {
    return await fn(dir);
  } finally {
    await rm(dir, { recursive: true, force: true }).catch(() => {});
  }
}

/** Resize to fit `max` px and encode JPEG. sharp first, ffmpeg as fallback (e.g. HEIC). */
export async function toJpeg(buf: Buffer, max: number, quality = 80): Promise<{ data: Buffer; width: number; height: number }> {
  try {
    const { data, info } = await sharp(buf, { failOn: "none" })
      .rotate()
      .resize({ width: max, height: max, fit: "inside", withoutEnlargement: true })
      .flatten({ background: "#ffffff" })
      .jpeg({ quality })
      .toBuffer({ resolveWithObject: true });
    return { data, width: info.width, height: info.height };
  } catch (e) {
    return withTmp(async (dir) => {
      const inp = path.join(dir, "in");
      const out = path.join(dir, "out.jpg");
      await writeFile(inp, buf);
      try {
        await run(FFMPEG, ["-y", "-i", inp, "-frames:v", "1", "-vf", `scale='min(${max},iw)':'min(${max},ih)':force_original_aspect_ratio=decrease`, "-q:v", "3", out], 60_000);
      } catch {
        throw new Error(`Cannot decode image: ${(e as Error).message.slice(0, 120)}`);
      }
      const data = await readFile(out);
      const m = await sharp(data).metadata();
      return { data, width: m.width ?? 0, height: m.height ?? 0 };
    });
  }
}

export async function imageSize(buf: Buffer): Promise<{ width: number; height: number } | null> {
  try {
    const m = await sharp(buf, { failOn: "none" }).metadata();
    const rotated = (m.orientation ?? 1) >= 5;
    return m.width && m.height ? (rotated ? { width: m.height, height: m.width } : { width: m.width, height: m.height }) : null;
  } catch {
    return null;
  }
}

export type Probe = { durationS: number; hasAudio: boolean; hasVideo: boolean; width: number; height: number };

export async function probe(file: string): Promise<Probe> {
  const { stdout } = await run(FFPROBE, ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", file], 60_000);
  const j = JSON.parse(stdout) as {
    format?: { duration?: string };
    streams?: Array<{ codec_type?: string; width?: number; height?: number; duration?: string; tags?: { rotate?: string }; side_data_list?: Array<{ rotation?: number }> }>;
  };
  const v = j.streams?.find((s) => s.codec_type === "video" && s.width);
  // Phones store portrait video as landscape plus a rotation; report what is shown.
  const rot = Math.abs(Number(v?.side_data_list?.find((d) => d.rotation != null)?.rotation ?? v?.tags?.rotate ?? 0)) % 180;
  const dur = Number(j.format?.duration ?? v?.duration ?? j.streams?.find((s) => s.codec_type === "audio")?.duration ?? 0);
  return {
    durationS: Number.isFinite(dur) ? dur : 0,
    hasAudio: !!j.streams?.some((s) => s.codec_type === "audio"),
    hasVideo: !!v,
    width: (rot === 90 ? v?.height : v?.width) ?? 0,
    height: (rot === 90 ? v?.width : v?.height) ?? 0,
  };
}

/** Up to `max` evenly spaced frames as JPEG buffers (768px wide at most). */
export async function extractFrames(file: string, dir: string, durationS: number, max = 8): Promise<Buffer[]> {
  const n = durationS < 2 ? 1 : Math.min(max, Math.max(2, Math.ceil(durationS / 2)));
  const out: Buffer[] = [];
  for (let i = 0; i < n; i++) {
    const t = durationS > 0 ? (durationS * (i + 0.5)) / n : 0;
    const dest = path.join(dir, `f${i}.jpg`);
    try {
      await run(FFMPEG, ["-y", "-ss", t.toFixed(2), "-i", file, "-frames:v", "1", "-vf", "scale='min(768,iw)':-2", "-q:v", "4", dest], 60_000);
      out.push(await readFile(dest));
    } catch {
      /* skip unreadable frame */
    }
  }
  return out;
}

const AUDIO_KBPS = 96;
const MAX_VIDEO_KBPS = 4000;
const MIN_VIDEO_KBPS = 200;

/**
 * Video bitrate (kbit/s) that keeps a [durationS] clip under [maxBytes]
 * with AAC audio and ~8% container headroom; null when even the minimum
 * quality would not fit.
 */
export function fitBitrate(durationS: number, maxBytes: number): number | null {
  if (!(durationS > 0)) return null;
  const totalKbps = (maxBytes * 8 * 0.92) / durationS / 1000;
  const video = Math.floor(Math.min(MAX_VIDEO_KBPS, totalKbps - AUDIO_KBPS));
  return video >= MIN_VIDEO_KBPS ? video : null;
}

/**
 * Re-encodes a video too large for storage as H.264/AAC MP4 (at most 1280px,
 * moov first so players can start before the end arrives). Returns the
 * path of a file of at most [maxBytes].
 */
export async function fitVideo(file: string, dir: string, durationS: number, maxBytes: number): Promise<string> {
  let kbps = fitBitrate(durationS, maxBytes);
  if (kbps == null) {
    throw new Error(`Video is too long to store (about ${Math.max(1, Math.floor(((maxBytes * 8 * 0.92) / ((MIN_VIDEO_KBPS + AUDIO_KBPS) * 1000)) / 60))} minutes at most)`);
  }
  for (let attempt = 0; attempt < 2; attempt++) {
    const out = path.join(dir, `fit${attempt}.mp4`);
    await run(
      FFMPEG,
      [
        "-y", "-i", file,
        "-map", "0:v:0", "-map", "0:a:0?",
        "-vf", "scale=w='min(1280,iw)':h='min(1280,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
        "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p",
        "-b:v", `${kbps}k`, "-maxrate", `${Math.round(kbps * 1.2)}k`, "-bufsize", `${kbps * 2}k`,
        "-c:a", "aac", "-b:a", `${AUDIO_KBPS}k`, "-ac", "2",
        "-movflags", "+faststart",
        out,
      ],
      15 * 60_000,
    );
    if ((await stat(out)).size <= maxBytes) return out;
    kbps = Math.floor(kbps * 0.7);
    if (kbps < MIN_VIDEO_KBPS) break;
  }
  throw new Error("Video could not be compressed enough to store");
}

const SEGMENT_S = 600;
const MAX_TRANSCRIBE_S = 3600;

async function groqTranscribe(audio: Buffer, name: string): Promise<string> {
  const t0 = Date.now();
  const form = new FormData();
  form.append("file", new Blob([new Uint8Array(audio)], { type: "audio/mpeg" }), name);
  form.append("model", "whisper-large-v3-turbo");
  form.append("response_format", "json");
  form.append("temperature", "0");
  let status = 0;
  try {
    const res = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
      method: "POST",
      headers: { Authorization: `Bearer ${config.groqApiKey}` },
      body: form,
      signal: AbortSignal.timeout(120_000),
    });
    status = res.status;
    if (!res.ok) throw new Error(`Groq transcription ${status}: ${(await res.text()).slice(0, 150)}`);
    const j = (await res.json()) as { text?: string };
    recordUsage({ provider: "groq", model: "whisper-large-v3-turbo", kind: "transcribe", ok: true, status, latencyMs: Date.now() - t0 });
    return (j.text ?? "").trim();
  } catch (e) {
    recordUsage({ provider: "groq", model: "whisper-large-v3-turbo", kind: "transcribe", ok: false, status: status || undefined, latencyMs: Date.now() - t0, errorMessage: (e as Error).message });
    throw e;
  }
}

/** Mono 16 kHz MP3 segments of 10 minutes (about 2.4 MB each), transcribed one by one. Returns "" for silence. */
export async function transcribe(file: string, dir: string, durationS: number): Promise<string> {
  if (!config.groqApiKey) throw new Error("GROQ_API_KEY missing, cannot transcribe");
  const total = Math.min(durationS || SEGMENT_S, MAX_TRANSCRIBE_S);
  const parts: string[] = [];
  for (let start = 0, i = 0; start < total; start += SEGMENT_S, i++) {
    const dest = path.join(dir, `a${i}.mp3`);
    await run(FFMPEG, ["-y", "-ss", String(start), "-t", String(SEGMENT_S), "-i", file, "-vn", "-ac", "1", "-ar", "16000", "-b:a", "48k", dest], 180_000);
    const buf = await readFile(dest);
    if (buf.length < 1500) continue;
    const text = await groqTranscribe(buf, `part${i}.mp3`);
    if (text) parts.push(text);
  }
  const all = parts.join("\n").trim();
  return /[\p{L}\p{N}]/u.test(all) ? all : "";
}
