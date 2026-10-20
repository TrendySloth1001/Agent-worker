import { createHash, timingSafeEqual } from "node:crypto";
import type { Request } from "express";
import { db } from "../db/prisma.js";
import { config } from "../config.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { copyObject, deleteObject, getRange, presign } from "../storage/s3.js";
import { apkVersionCode, expectedVersionCode } from "./apk.js";
import type { StagedApk } from "./upload.js";
import { toRows, type EventsBody, type Stage, installSuccessRate } from "./events.js";
import type { AppRelease } from "../generated/prisma/client.js";
import {
  apkKeyFor,
  canDelete,
  decideUpdate,
  duplicateBuild,
  publishedAtFor,
  type CreateBody,
  type Kind,
  type LiveRelease,
  type PatchBody,
  type Status,
} from "./logic.js";

const URL_TTL_S = 3600;

export type PublicRelease = { version: string; build: number; kind: Kind; title: string; notes: string[]; size: number; sha256: string; url: string };
export type OwnerRelease = PublicRelease & {
  id: string;
  status: Status;
  minSupportedBuild: number | null;
  createdAt: string;
  publishedAt: string | null;
};

const notesOf = (r: AppRelease): string[] => (Array.isArray(r.notes) ? r.notes.filter((n): n is string => typeof n === "string") : []);

async function toPublic(r: AppRelease, kind: Kind = r.kind as Kind): Promise<PublicRelease> {
  return {
    version: r.version,
    build: r.build,
    kind,
    title: r.title,
    notes: notesOf(r),
    size: Number(r.size),
    sha256: r.sha256,
    url: await presign(r.apkKey, URL_TTL_S),
  };
}

async function toOwner(r: AppRelease): Promise<OwnerRelease> {
  return {
    ...(await toPublic(r)),
    id: r.id,
    status: r.status as Status,
    minSupportedBuild: r.minSupportedBuild,
    createdAt: r.createdAt.toISOString(),
    publishedAt: r.publishedAt?.toISOString() ?? null,
  };
}

/** GET /app/update body. Also records the caller's build for the adoption view. */
/** A short-lived link to the newest live APK, for the public download page; null when nothing is live. */
export async function latestApkUrl(ttlSeconds = 600): Promise<{ url: string; version: string; build: number } | null> {
  const r = await db().appRelease.findFirst({ where: { status: "live" }, orderBy: { build: "desc" } });
  if (!r) return null;
  return { url: await presign(r.apkKey, ttlSeconds), version: r.version, build: r.build };
}

export async function checkForUpdate(current: number, userId: string | null, deviceId: string | null = null) {
  const rows = await db().appRelease.findMany({ where: { status: "live" }, orderBy: { build: "desc" } });
  const live: Array<LiveRelease & { row: AppRelease }> = rows.map((row) => ({ build: row.build, kind: row.kind as Kind, minSupportedBuild: row.minSupportedBuild, row }));
  const d = decideUpdate(live, current);
  if (userId) {
    // Fire and forget: a failed adoption write must never fail the update check.
    const version = rows.find((r) => r.build === current)?.version ?? "";
    db()
      .appInstall.upsert({
        where: { userId },
        create: { userId, build: current, version, deviceId },
        update: { build: current, version, seenAt: new Date(), ...(deviceId && { deviceId }) },
      })
      .catch((e: unknown) => log.warn("app_installs upsert failed", { err: String(e) }));
  }
  const latestRow = d.latest ? (d.latest as (typeof live)[number]).row : null;
  return {
    current,
    latest: latestRow && d.kind ? await toPublic(latestRow, d.kind) : null,
    minSupportedBuild: d.minSupportedBuild,
    required: d.required,
  };
}

export async function listReleases() {
  const [rows, groups, stages] = await Promise.all([
    db().appRelease.findMany({ orderBy: { build: "desc" } }),
    db().appInstall.groupBy({ by: ["build", "version"], _count: { _all: true }, orderBy: { build: "desc" } }),
    db().appInstallEvent.groupBy({ by: ["toBuild", "stage"], _count: { _all: true } }),
  ]);
  const byBuild = new Map<number, Array<{ stage: Stage; count: number }>>();
  for (const s of stages) {
    const list = byBuild.get(s.toBuild) ?? [];
    list.push({ stage: s.stage as Stage, count: s._count._all });
    byBuild.set(s.toBuild, list);
  }
  return {
    releases: await Promise.all(rows.map(toOwner)),
    adoption: groups.map((g) => ({ build: g.build, version: g.version, users: g._count._all })),
    /** Install attempts per target build: event counts by stage plus the success rate (null with no attempts). */
    installs: [...byBuild].map(([build, counts]) => ({ build, stages: counts, successRate: installSuccessRate(counts) })),
  };
}

/** POST /app/health/events: stores a batch of install-outcome events for the signed-in user. */
export async function recordInstallEvents(body: EventsBody, userId: string): Promise<number> {
  const rows = toRows(body, userId);
  const r = await db().appInstallEvent.createMany({ data: rows });
  if (body.deviceId) {
    // Remember the device on the adoption row (best effort; the row exists once /app/update ran).
    db()
      .appInstall.updateMany({ where: { userId }, data: { deviceId: body.deviceId } })
      .catch((e: unknown) => log.warn("app_installs device update failed", { err: String(e) }));
  }
  return r.count;
}

/** The storage calls createRelease makes (replaced in tests). */
export const releaseStorage = {
  copy: copyObject,
  remove: deleteObject,
  range: getRange,
};

/**
 * Publishes an APK that was already streamed to S3 under a staging key: checks its versionCode is
 * 2000 + build (so a signed APK cannot be filed under another build number), moves it to its final key
 * and records it. The staging object is always removed.
 */
export async function createRelease(body: CreateBody, staged: StagedApk): Promise<OwnerRelease> {
  const st = releaseStorage;
  try {
    if (await db().appRelease.findUnique({ where: { build: body.build }, select: { id: true } })) throw duplicateBuild(body.build);
    let code: number;
    try {
      code = await apkVersionCode(staged.size, (off, len) => st.range(staged.key, off, Math.min(len, staged.size - off)));
    } catch (e) {
      if (e instanceof AppError) throw e;
      log.warn("apk manifest unreadable", { err: String(e) });
      throw new AppError(400, "bad_request", "Couldn't read the APK's manifest. Is this a valid APK?");
    }
    if (code !== expectedVersionCode(body.build)) {
      throw new AppError(400, "bad_request", `APK versionCode is ${code} but build ${body.build} needs ${expectedVersionCode(body.build)}`);
    }
    const apkKey = apkKeyFor(body.build, body.version);
    await st.copy(staged.key, apkKey);
    try {
      return await insertRelease(body, apkKey, staged);
    } catch (e) {
      await st.remove(apkKey).catch(() => undefined);
      throw e;
    }
  } finally {
    await st.remove(staged.key).catch((e: unknown) => log.warn("staged apk delete failed", { err: String(e) }));
  }
}

async function insertRelease(body: CreateBody, apkKey: string, staged: StagedApk): Promise<OwnerRelease> {
  const sha256 = staged.sha256;
  try {
    const row = await db().appRelease.create({
      data: {
        version: body.version,
        build: body.build,
        kind: body.kind,
        title: body.title,
        notes: body.notes,
        apkKey,
        sha256,
        size: BigInt(staged.size),
        minSupportedBuild: body.minSupportedBuild ?? null,
        status: body.status,
        publishedAt: body.status === "live" ? new Date() : null,
      },
    });
    return toOwner(row);
  } catch (e) {
    if ((e as { code?: string }).code === "P2002") throw duplicateBuild(body.build);
    throw e;
  }
}

async function getRow(id: string): Promise<AppRelease> {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) throw new AppError(404, "not_found", "Release not found");
  const row = await db().appRelease.findUnique({ where: { id } });
  if (!row) throw new AppError(404, "not_found", "Release not found");
  return row;
}

export async function patchRelease(id: string, p: PatchBody): Promise<OwnerRelease> {
  const row = await getRow(id);
  const row2 = await db().appRelease.update({
    where: { id },
    data: {
      ...(p.status !== undefined && { status: p.status }),
      ...(p.kind !== undefined && { kind: p.kind }),
      ...(p.title !== undefined && { title: p.title }),
      ...(p.notes !== undefined && { notes: p.notes }),
      ...(p.minSupportedBuild !== undefined && { minSupportedBuild: p.minSupportedBuild }),
      publishedAt: publishedAtFor(row.status, p.status, row.publishedAt),
    },
  });
  return toOwner(row2);
}

export async function deleteRelease(id: string): Promise<void> {
  const row = await getRow(id);
  if (!canDelete(row.status)) throw new AppError(409, "conflict", "Pull a live release before deleting it");
  await deleteObject(row.apkKey).catch((e: unknown) => log.warn("release apk delete failed", { err: String(e) }));
  await db().appRelease.delete({ where: { id } });
}

/** True when the request carries `Authorization: Bearer <RELEASE_TOKEN>` (constant-time compare; disabled when unset). */
export function hasReleaseToken(req: Request): boolean {
  const expected = config.releaseToken;
  if (!expected) return false;
  const h = req.headers.authorization ?? "";
  if (!h.startsWith("Bearer ")) return false;
  const got = createHash("sha256").update(h.slice(7).trim()).digest();
  const want = createHash("sha256").update(expected).digest();
  return timingSafeEqual(got, want);
}
