import { z } from "zod";

/** Stages an app reports while updating. `ok` is implied by the stage. */
export const STAGES = [
  "download_start",
  "download_ok",
  "download_fail",
  "verify_fail",
  "signature_mismatch",
  "install_start",
  "install_ok",
  "install_fail",
  "cancelled",
  "first_launch_ok",
] as const;
export type Stage = (typeof STAGES)[number];
export const VIAS = ["full", "delta", "resume"] as const;

export const MAX_EVENTS = 50;
/** Events older than this are clamped to now (a long-offline device still counts, but cannot rewrite history). */
export const MAX_AGE_MS = 7 * 24 * 3600 * 1000;
const FAILED = new Set<Stage>(["download_fail", "verify_fail", "signature_mismatch", "install_fail"]);
export const stageOk = (s: Stage): boolean => !FAILED.has(s);

const build = z.number().int().min(0).max(2_000_000_000);
const eventSchema = z.object({
  /** Epoch milliseconds when the step happened on the device. */
  at: z.number().int().optional(),
  build,
  toBuild: build,
  stage: z.enum(STAGES),
  code: z
    .string()
    .trim()
    .max(40)
    .regex(/^[A-Za-z0-9_.:-]*$/, "code has invalid characters")
    .optional(),
  bytes: z
    .number()
    .int()
    .min(0)
    .max(2 ** 40)
    .optional(),
  via: z.enum(VIAS).default("full"),
});

export const eventsBody = z.object({
  deviceId: z
    .string()
    .trim()
    .regex(/^[A-Za-z0-9-]{8,64}$/, "deviceId is invalid")
    .optional(),
  events: z.array(eventSchema).min(1, "No events").max(MAX_EVENTS, `At most ${MAX_EVENTS} events per request`),
});
export type EventsBody = z.infer<typeof eventsBody>;

export type EventRow = {
  userId: string;
  deviceId: string | null;
  at: Date;
  build: number;
  toBuild: number;
  stage: Stage;
  ok: boolean;
  code: string | null;
  bytes: bigint | null;
  via: (typeof VIAS)[number];
};

/** Validated body to DB rows: the user comes from the session, never the body. */
export function toRows(body: EventsBody, userId: string, now = new Date()): EventRow[] {
  return body.events.map((e) => {
    const t = e.at ?? now.getTime();
    const at = new Date(t > now.getTime() || t < now.getTime() - MAX_AGE_MS ? now.getTime() : t);
    return {
      userId,
      deviceId: body.deviceId ?? null,
      at,
      build: e.build,
      toBuild: e.toBuild,
      stage: e.stage,
      ok: stageOk(e.stage),
      code: e.code ? e.code : null,
      bytes: e.bytes != null ? BigInt(e.bytes) : null,
      via: e.via,
    };
  });
}

export type StageCount = { stage: Stage; count: number };
/** Install success per design 4.3: install_ok / (install_ok + install_fail + verify_fail); cancelled excluded. null when no attempts. */
export function installSuccessRate(counts: StageCount[]): number | null {
  const n = (s: Stage) => counts.find((c) => c.stage === s)?.count ?? 0;
  const denom = n("install_ok") + n("install_fail") + n("verify_fail");
  return denom === 0 ? null : n("install_ok") / denom;
}
