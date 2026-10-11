import type { NextFunction, Request, Response } from "express";
import { config } from "../config.js";
import { db } from "../db/prisma.js";
import { AppError } from "../util/errors.js";
import type { AuthUser } from "./context.js";

export type Limits = { chat: number; table: number; uploads: number; storageBytes: number };
export type Usage = { chats: number; tables: number; uploads: number; bytes: number; storageBytes: number };

/** UTC day the counters belong to, as YYYY-MM-DD. */
const today = () => new Date().toISOString().slice(0, 10);
/** The same day as a DATE column value. */
const todayDate = () => new Date(`${today()}T00:00:00.000Z`);

export function resetsAt(): string {
  const d = new Date();
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1)).toISOString();
}

const resetLabel = () => `${resetsAt().slice(11, 16)} UTC`;

/** Limits for a user (configured defaults plus per-user overrides); null = unlimited (owner). */
export async function limitsFor(user: AuthUser): Promise<Limits | null> {
  if (user.role === "owner" || !user.id) return null;
  const row = await db().user.findUnique({ where: { id: user.id }, select: { limits: true } });
  const o = (row?.limits ?? {}) as Partial<Limits>;
  const pick = (k: keyof Limits) => (typeof o[k] === "number" && o[k]! >= 0 ? o[k]! : config.limits[k]);
  return { chat: pick("chat"), table: pick("table"), uploads: pick("uploads"), storageBytes: pick("storageBytes") };
}

export async function usageFor(userId: string | null): Promise<Usage> {
  const [day, storage] = await Promise.all([
    userId ? db().userDailyUsage.findUnique({ where: { userId_day: { userId, day: todayDate() } } }) : null,
    db().storedFile.aggregate({ where: { userId }, _sum: { size: true } }),
  ]);
  return {
    chats: day?.chats ?? 0,
    tables: day?.tables ?? 0,
    uploads: day?.uploads ?? 0,
    bytes: Number(day?.bytes ?? 0),
    storageBytes: Number(storage._sum.size ?? 0),
  };
}

function limitError(what: string, limit: number): AppError {
  if (limit <= 0) return new AppError(429, "daily_limit", `${what[0].toUpperCase()}${what.slice(1)} are not available on your account.`);
  return new AppError(429, "daily_limit", `You've used all ${limit} ${what} for today. Your limit resets at ${resetLabel()}.`);
}

/** Counts a /chat request (and a Round Table run) against today's limits; 429 when over. */
export async function chatLimit(req: Request, _res: Response, next: NextFunction): Promise<void> {
  const user = req.user;
  if (!user?.id) return next();
  const table = req.body?.roundTable === true ? 1 : 0;
  const limits = await limitsFor(user);
  if (!limits) {
    // Unlimited, but still counted for the profile screen.
    await db().userDailyUsage.upsert({
      where: { userId_day: { userId: user.id, day: todayDate() } },
      create: { userId: user.id, day: todayDate(), chats: 1, tables: table },
      update: { chats: { increment: 1 }, tables: { increment: table } },
    });
    return next();
  }
  if (limits.chat <= 0) return next(limitError("chat requests", limits.chat));
  if (table && limits.table <= 0) return next(limitError("Round Table runs", limits.table));
  // Insert-or-increment only while under both limits; no row back means over.
  // Raw: a conditional upsert (count only while under the limits) is one atomic statement.
  const rows = await db().$queryRaw<Array<{ chats: number }>>`
    INSERT INTO user_daily_usage (user_id, day, chats, tables) VALUES (${user.id}::uuid, ${today()}::date, 1, ${table}::int)
    ON CONFLICT (user_id, day) DO UPDATE SET chats = user_daily_usage.chats + 1, tables = user_daily_usage.tables + ${table}::int
      WHERE user_daily_usage.chats < ${limits.chat}::numeric AND user_daily_usage.tables + ${table}::int <= ${limits.table}::numeric
    RETURNING chats`;
  if (rows[0]) return next();
  const used = await usageFor(user.id);
  next(used.chats >= limits.chat ? limitError("chat requests", limits.chat) : limitError("Round Table runs", limits.table));
}

/** Checks the upload count and storage quota before a file of [size] bytes is stored. */
export async function checkUpload(user: AuthUser, size: number): Promise<void> {
  const limits = await limitsFor(user);
  if (!limits) return;
  const used = await usageFor(user.id);
  if (used.uploads >= limits.uploads) throw limitError("uploads", limits.uploads);
  if (used.storageBytes + size > limits.storageBytes) {
    const mb = Math.round(limits.storageBytes / 1024 / 1024);
    throw new AppError(429, "storage_limit", `Your files would exceed your ${mb} MB of storage. Delete some chats with attachments to free space.`);
  }
}

export async function recordUpload(user: AuthUser, size: number): Promise<void> {
  if (!user.id) return;
  await db().userDailyUsage.upsert({
    where: { userId_day: { userId: user.id, day: todayDate() } },
    create: { userId: user.id, day: todayDate(), uploads: 1, bytes: size },
    update: { uploads: { increment: 1 }, bytes: { increment: size } },
  });
}
