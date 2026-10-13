import { z } from "zod";
import { AppError } from "../util/errors.js";

export const KINDS = ["patch", "feature", "major", "critical"] as const;
export type Kind = (typeof KINDS)[number];
export const STATUSES = ["draft", "live", "pulled"] as const;
export type Status = (typeof STATUSES)[number];

export const MAX_NOTES = 6;
export const MAX_APK_BYTES = 150 * 1024 * 1024;
export const VERSION_RE = /^\d+\.\d+\.\d+$/;

const SEVERITY: Record<Kind, number> = { patch: 0, feature: 1, major: 2, critical: 3 };

/** The most severe kind (critical > major > feature > patch). */
export function mostSevere(kinds: Kind[]): Kind {
  return kinds.reduce<Kind>((a, b) => (SEVERITY[b] > SEVERITY[a] ? b : a), "patch");
}

export type LiveRelease = { build: number; kind: Kind; minSupportedBuild: number | null };

/** Live releases newer than the client's build. */
export function newerThan<T extends { build: number }>(live: T[], current: number): T[] {
  return live.filter((r) => r.build > current);
}

/** The highest-build release among [live] newer than [current], or null. */
export function pickLatest<T extends { build: number }>(live: T[], current: number): T | null {
  return newerThan(live, current).reduce<T | null>((a, r) => (!a || r.build > a.build ? r : a), null);
}

/** Kind to report: the most severe among all live releases newer than [current] (patch if none). */
export function escalatedKind(live: LiveRelease[], current: number): Kind {
  return mostSevere(newerThan(live, current).map((r) => r.kind));
}

/** max(min_supported_build) over live releases, null if none set. */
export function minSupported(live: LiveRelease[]): number | null {
  const vals = live.map((r) => r.minSupportedBuild).filter((v): v is number => v != null);
  return vals.length ? Math.max(...vals) : null;
}

/** Update is mandatory: the reported kind is critical, or the client is below the minimum supported build. */
export function isRequired(kind: Kind | null, minSupportedBuild: number | null, current: number): boolean {
  return kind === "critical" || (minSupportedBuild != null && current < minSupportedBuild);
}

export type UpdateDecision = { kind: Kind | null; latest: LiveRelease | null; minSupportedBuild: number | null; required: boolean };

/** Everything GET /app/update decides from the live releases, as one pure function. */
export function decideUpdate(live: LiveRelease[], current: number): UpdateDecision {
  const latest = pickLatest(live, current);
  const min = minSupported(live);
  const kind = latest ? escalatedKind(live, current) : null;
  return { kind, latest, minSupportedBuild: min, required: isRequired(kind, min, current) };
}

export const apkKeyFor = (build: number, version: string) => `releases/${build}/sparky-${version}-arm64.apk`;

// ---- validation ----

const int = (name: string) => z.coerce.number({ message: `${name} must be a number` }).int(`${name} must be an integer`).min(0, `${name} must be positive`).max(2_000_000_000);
const notesList = z
  .array(z.string().trim().min(1).max(300))
  .max(MAX_NOTES, `At most ${MAX_NOTES} notes`);

export const createBody = z.object({
  version: z.string().trim().regex(VERSION_RE, "version must look like 1.2.3"),
  build: int("build").min(1),
  kind: z.enum(KINDS, { message: `kind must be one of ${KINDS.join(", ")}` }),
  title: z.string().trim().max(120).default(""),
  notes: z.string().default("[]").transform((s, ctx) => {
    let v: unknown;
    try {
      v = JSON.parse(s || "[]");
    } catch {
      ctx.addIssue({ code: "custom", message: "notes must be a JSON array of strings" });
      return z.NEVER;
    }
    const r = notesList.safeParse(v);
    if (!r.success) {
      ctx.addIssue({ code: "custom", message: r.error.issues[0]?.message ?? "invalid notes" });
      return z.NEVER;
    }
    return r.data;
  }),
  minSupportedBuild: z.preprocess((v) => (v === "" || v == null ? undefined : v), int("minSupportedBuild").optional()),
  status: z.preprocess((v) => (v === "" ? undefined : v), z.enum(["draft", "live"]).default("draft")),
});
export type CreateBody = z.infer<typeof createBody>;

export const patchBody = z
  .object({
    status: z.enum(STATUSES),
    kind: z.enum(KINDS),
    title: z.string().trim().max(120),
    notes: notesList,
    minSupportedBuild: int("minSupportedBuild").nullable(),
  })
  .partial()
  .strict();
export type PatchBody = z.infer<typeof patchBody>;

/** Parses with zod, turning the first issue into a 400. */
export function parseOr400<T>(schema: z.ZodType<T>, input: unknown): T {
  const r = schema.safeParse(input);
  if (!r.success) throw new AppError(400, "bad_request", r.error.issues[0]?.message ?? "Invalid request");
  return r.data;
}

export const duplicateBuild = (build: number) => new AppError(409, "conflict", `Build ${build} already exists`);

/** Release status changes allowed: a pulled release can go live again; deleting needs draft/pulled. */
export const canDelete = (status: string) => status === "draft" || status === "pulled";

export function publishedAtFor(prevStatus: string, next: Status | undefined, prevPublishedAt: Date | null, now = new Date()): Date | null {
  if (next === "live" && prevStatus !== "live") return now;
  return prevPublishedAt;
}
