import { createHash, timingSafeEqual } from "node:crypto";
import type { Request } from "express";
import { db } from "../db/prisma.js";
import { config } from "../config.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { deleteObject, presign, putObject } from "../storage/s3.js";
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
export async function checkForUpdate(current: number, userId: string | null) {
  const rows = await db().appRelease.findMany({ where: { status: "live" }, orderBy: { build: "desc" } });
  const live: Array<LiveRelease & { row: AppRelease }> = rows.map((row) => ({ build: row.build, kind: row.kind as Kind, minSupportedBuild: row.minSupportedBuild, row }));
  const d = decideUpdate(live, current);
  if (userId) {
    // Fire and forget: a failed adoption write must never fail the update check.
    const version = rows.find((r) => r.build === current)?.version ?? "";
    db()
      .appInstall.upsert({
        where: { userId },
        create: { userId, build: current, version },
        update: { build: current, version, seenAt: new Date() },
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
  const [rows, groups] = await Promise.all([
    db().appRelease.findMany({ orderBy: { build: "desc" } }),
    db().appInstall.groupBy({ by: ["build", "version"], _count: { _all: true }, orderBy: { build: "desc" } }),
  ]);
  return {
    releases: await Promise.all(rows.map(toOwner)),
    adoption: groups.map((g) => ({ build: g.build, version: g.version, users: g._count._all })),
  };
}

export async function createRelease(body: CreateBody, apk: Buffer): Promise<OwnerRelease> {
  if (await db().appRelease.findUnique({ where: { build: body.build }, select: { id: true } })) throw duplicateBuild(body.build);
  const sha256 = createHash("sha256").update(apk).digest("hex");
  const apkKey = apkKeyFor(body.build, body.version);
  await putObject(apkKey, apk, "application/vnd.android.package-archive");
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
        size: BigInt(apk.length),
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
