import { createHash } from "node:crypto";
import { z } from "zod";
import { redact } from "../nlp/pii.js";

/** Pure logic for in-house crash/error reporting (OTA v2 phase 2): validation, scrubbing, fingerprints, math. */

export const ERROR_KINDS = ["dart", "platform", "isolate", "kotlin", "anr", "native_signal"] as const;
export type ErrorKind = (typeof ERROR_KINDS)[number];
export const SESSION_OUTCOMES = ["ok", "crash", "anr", "killed", "unknown"] as const;
export type SessionOutcome = (typeof SESSION_OUTCOMES)[number];
export const GROUP_STATUSES = ["open", "resolved", "ignored"] as const;
export type GroupStatus = (typeof GROUP_STATUSES)[number];

export const MESSAGE_MAX = 200;
export const STACK_MAX = 8 * 1024;
export const TYPE_MAX = 80;
export const TITLE_MAX = 140;
export const BREADCRUMBS_MAX = 30;
export const CRUMB_MSG_MAX = 80;
export const ERROR_BATCH_MAX = 10;
export const SESSION_BATCH_MAX = 20;
export const SAMPLES_PER_BUILD = 5;
export const USER_DAILY_SAMPLE_CAP = 200;
export const ERROR_RETENTION_DAYS = 30;
export const SESSION_RETENTION_DAYS = 90;
/** Sessions younger than this may still be running, so crash-free math leaves them out. */
export const SESSION_SETTLE_MS = 5 * 60_000;
/** Client timestamps older than this (or in the future) are replaced by the server clock. */
export const MAX_EVENT_AGE_MS = 8 * 24 * 3600_000;
const FRAMES_KEPT = 3;

/** Only these fields of `device` are ever stored. */
const DEVICE_STRING_KEYS = ["model", "abi", "locale", "memBucket", "net"] as const;

const cut = (n: number) => z.string().transform((s) => s.slice(0, n));

const crumb = z.object({ t: z.coerce.number().int().optional(), c: cut(20), m: cut(CRUMB_MSG_MAX).default("") });

const deviceSchema = z
  .object({
    model: cut(60).optional(),
    sdk: z.coerce.number().int().min(0).max(100).optional(),
    abi: cut(20).optional(),
    locale: cut(20).optional(),
    fg: z.boolean().optional(),
    memBucket: cut(20).optional(),
    net: cut(20).optional(),
  })
  .strip();

export const errorItem = z.object({
  kind: z.enum(ERROR_KINDS),
  type: cut(TYPE_MAX).default("Error"),
  message: cut(2000).default(""),
  stack: cut(STACK_MAX * 2).default(""),
  breadcrumbs: z
    .array(crumb)
    .default([])
    .transform((a) => a.slice(-BREADCRUMBS_MAX)),
  device: deviceSchema.default({}),
  build: z.coerce.number().int().min(0).max(2_000_000_000),
  at: z.coerce.number().int().optional(),
  sessionId: z.string().uuid().optional(),
});
export type ErrorItem = z.infer<typeof errorItem>;
export const errorsBody = z.object({ errors: z.array(errorItem).min(1).max(ERROR_BATCH_MAX) });

export const sessionItem = z.object({
  id: z.string().uuid(),
  build: z.coerce.number().int().min(0).max(2_000_000_000),
  patchNumber: z.coerce.number().int().min(0).max(1_000_000).optional(),
  startedAt: z.coerce.number().int(),
  endedAt: z.coerce.number().int().optional(),
  outcome: z.enum(SESSION_OUTCOMES).default("unknown"),
});
export type SessionItem = z.infer<typeof sessionItem>;
export const sessionsBody = z.object({ sessions: z.array(sessionItem).min(1).max(SESSION_BATCH_MAX) });

// ---- PII scrubbing -------------------------------------------------------------------

/** Free text (messages, breadcrumb text): every PII kind is redacted. */
export const scrubText = (s: string, max: number): string => redact(s.slice(0, max * 2)).slice(0, max);

/**
 * Stack traces: only secrets and emails are redacted. Phone/card/IP detectors would mangle the long hex
 * addresses of obfuscated traces and break symbolization.
 */
export const scrubStack = (s: string): string =>
  redact(s.slice(0, STACK_MAX * 2), ["private_key", "jwt", "api_key", "password", "email"]).slice(0, STACK_MAX);

// ---- fingerprinting ------------------------------------------------------------------

const APP_FRAME = /package:app\/|\bcom\.sparky\.app\b/;
const OBFUSCATED_FRAME = /^\s*#\d+\s+abs\s+[0-9a-f]+\s+virt\s+([0-9a-f]+)/i;
const FRAME_LINE = /^\s*(#\d+\b|at\s)/;

/** One frame without addresses, line/column numbers and anonymous ids; null for non-frame lines. */
export function normalizeFrame(line: string): { text: string; app: boolean } | null {
  const virt = OBFUSCATED_FRAME.exec(line);
  // Obfuscated AOT frames carry no names: the virtual offset is stable within a build and identifies the frame.
  if (virt) return { text: `virt:${virt[1].toLowerCase().replace(/^0+/, "")}`, app: true };
  if (!FRAME_LINE.test(line)) return null;
  const app = APP_FRAME.test(line);
  const text = line
    .replace(/^\s*#\d+\s+/, "")
    .replace(/^\s*at\s+/, "")
    .replace(/0x[0-9a-f]+/gi, "")
    .replace(/:\d+(:\d+)?\)/g, ")") // dart ":12:5)"
    .replace(/\(([^():]+\.(kt|java)):\d+\)/g, "($1)") // kotlin "(Foo.kt:12)"
    .replace(/\$\d+/g, "$") // anonymous class/lambda ids
    .replace(/\s+/g, " ")
    .trim();
  return { text, app };
}

/**
 * The frames that identify a stack: up to 3 app frames (package:app/..., com.sparky.app..., or obfuscated
 * offsets), preceded by the first frame when that is a framework/library frame. Later framework frames
 * (dart:async, flutter internals) vary with the call path and are dropped.
 */
export function significantFrames(stack: string): string[] {
  const out: string[] = [];
  let first = true;
  let app = 0;
  for (const line of stack.split("\n")) {
    const f = normalizeFrame(line);
    if (!f) continue;
    if (f.app) {
      if (app < FRAMES_KEPT) out.push(f.text);
      app++;
    } else if (first) out.push(f.text);
    first = false;
    if (app >= FRAMES_KEPT) break;
  }
  return out;
}

/** sha1(kind + type + significant frames). Messages are excluded: they carry values that vary per user. */
export function fingerprintOf(kind: string, type: string, stack: string, message = ""): string {
  const frames = significantFrames(stack);
  // Without frames (ANR, native signal, a throw with no trace) the stable part of the message tells errors apart.
  const tail = frames.length ? frames.join("|") : `msg:${message.replace(/\d+/g, "#").slice(0, 80)}`;
  return createHash("sha1").update(`${kind}|${type.trim()}|${tail}`).digest("hex");
}

// ---- preparing one event -------------------------------------------------------------

export type PreparedError = {
  fingerprint: string;
  kind: ErrorKind;
  type: string;
  title: string;
  message: string;
  stack: string;
  breadcrumbs: Array<{ t?: number; c: string; m: string }>;
  device: Record<string, string | number | boolean>;
  build: number;
  at: Date;
  sessionId: string | null;
};

/** Client time if plausible (not future, not older than a week), else the server clock. */
export function clampAt(at: number | undefined, now: number): Date {
  if (at == null || at > now + 60_000 || at < now - MAX_EVENT_AGE_MS) return new Date(now);
  return new Date(at);
}

export function cleanDevice(d: ErrorItem["device"]): PreparedError["device"] {
  const out: PreparedError["device"] = {};
  for (const k of DEVICE_STRING_KEYS) if (d[k]) out[k] = scrubText(d[k] as string, 60);
  if (d.sdk != null) out.sdk = d.sdk;
  if (d.fg != null) out.fg = d.fg;
  return out;
}

export function prepareError(item: ErrorItem, now = Date.now()): PreparedError {
  // The fingerprint is computed from the raw stack so redaction never changes grouping.
  const fingerprint = fingerprintOf(item.kind, item.type, item.stack, item.message);
  const message = scrubText(item.message, MESSAGE_MAX);
  const type = scrubText(item.type, TYPE_MAX);
  const firstLine = message.split("\n")[0];
  return {
    fingerprint,
    kind: item.kind,
    type,
    title: (firstLine ? `${type}: ${firstLine}` : type).slice(0, TITLE_MAX),
    message,
    stack: scrubStack(item.stack),
    breadcrumbs: item.breadcrumbs.map((b) => ({ ...(b.t != null ? { t: b.t } : {}), c: scrubText(b.c, 20), m: scrubText(b.m, CRUMB_MSG_MAX) })),
    device: cleanDevice(item.device),
    build: item.build,
    at: clampAt(item.at, now),
    sessionId: item.sessionId ?? null,
  };
}

// ---- decisions and math --------------------------------------------------------------

/** Keep a sample event only while the (group, build) holds fewer than 5 and the user is under the daily cap. */
export function shouldStoreSample(samplesForBuild: number, userSamplesToday: number): boolean {
  return samplesForBuild < SAMPLES_PER_BUILD && userSamplesToday < USER_DAILY_SAMPLE_CAP;
}

/** Crash-free sessions: 1 - crashed/total, null with no sessions. Rounded to 4 decimals (99.87% -> 0.9987). */
export function crashFreeRate(total: number, crashed: number): number | null {
  if (total <= 0) return null;
  return Math.round((1 - Math.min(crashed, total) / total) * 10_000) / 10_000;
}

/** A resolved group reopens when it is seen again on a build newer than the one it was last seen on. */
export function statusAfterHit(status: string, buildSeen: number, lastBuild: number): GroupStatus {
  if (status === "resolved" && buildSeen > lastBuild) return "open";
  return (GROUP_STATUSES as readonly string[]).includes(status) ? (status as GroupStatus) : "open";
}

/** A session keeps its first known outcome; a crash/ANR report may replace a guessed "killed". */
export function mergeOutcome(prev: SessionOutcome, next: SessionOutcome): SessionOutcome {
  if (prev === "unknown") return next;
  if (prev === "killed" && (next === "crash" || next === "anr")) return next;
  return prev;
}

export const retentionCutoff = (now: number, days: number): Date => new Date(now - days * 24 * 3600_000);
export const isCrashed = (o: string): boolean => o === "crash" || o === "anr";
