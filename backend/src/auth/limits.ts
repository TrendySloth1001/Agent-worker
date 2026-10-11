import type { NextFunction, Request, Response } from "express";
import { config } from "../config.js";
import { query } from "../db/pool.js";
import { AppError } from "../util/errors.js";
import type { AuthUser } from "./context.js";

export type Limits = { chat: number; table: number; uploads: number; storageBytes: number };
export type Usage = { chats: number; tables: number; uploads: number; bytes: number; storageBytes: number };

/** UTC day the counters belong to, as YYYY-MM-DD. */
const today = () => new Date().toISOString().slice(0, 10);

export function resetsAt(): string {
  const d = new Date();
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1)).toISOString();
}

const resetLabel = () => `${resetsAt().slice(11, 16)} UTC`;

/** Limits for a user (configured defaults plus per-user overrides); null = unlimited (owner). */
export async function limitsFor(user: AuthUser): Promise<Limits | null> {
  if (user.role === "owner" || !user.id) return null;
  const { rows } = await query<{ limits: Partial<Limits> }>("SELECT limits FROM users WHERE id = $1", [user.id]);
  const o = rows[0]?.limits ?? {};
  const pick = (k: keyof Limits) => (typeof o[k] === "number" && o[k]! >= 0 ? o[k]! : config.limits[k]);
  return { chat: pick("chat"), table: pick("table"), uploads: pick("uploads"), storageBytes: pick("storageBytes") };
}

export async function usageFor(userId: string | null): Promise<Usage> {
  const { rows } = await query<{ chats: number; tables: number; uploads: number; bytes: string; storage: string }>(
    `SELECT COALESCE(u.chats, 0) AS chats, COALESCE(u.tables, 0) AS tables, COALESCE(u.uploads, 0) AS uploads, COALESCE(u.bytes, 0) AS bytes,
            (SELECT COALESCE(sum(size), 0) FROM files WHERE user_id IS NOT DISTINCT FROM $1) AS storage
       FROM (SELECT 1) one LEFT JOIN user_daily_usage u ON u.user_id = $1 AND u.day = $2`,
    [userId, today()],
  );
  const r = rows[0];
  return { chats: r.chats, tables: r.tables, uploads: r.uploads, bytes: Number(r.bytes), storageBytes: Number(r.storage) };
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
    await query(
      `INSERT INTO user_daily_usage (user_id, day, chats, tables) VALUES ($1, $2, 1, $3)
       ON CONFLICT (user_id, day) DO UPDATE SET chats = user_daily_usage.chats + 1, tables = user_daily_usage.tables + $3`,
      [user.id, today(), table],
    );
    return next();
  }
  if (limits.chat <= 0) return next(limitError("chat requests", limits.chat));
  if (table && limits.table <= 0) return next(limitError("Round Table runs", limits.table));
  // Insert-or-increment only while under both limits; no row back means over.
  const { rows } = await query(
    `INSERT INTO user_daily_usage (user_id, day, chats, tables) VALUES ($1, $2, 1, $3)
     ON CONFLICT (user_id, day) DO UPDATE SET chats = user_daily_usage.chats + 1, tables = user_daily_usage.tables + $3
       WHERE user_daily_usage.chats < $4 AND user_daily_usage.tables + $3 <= $5
     RETURNING chats`,
    [user.id, today(), table, limits.chat, limits.table],
  );
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
  await query(
    `INSERT INTO user_daily_usage (user_id, day, uploads, bytes) VALUES ($1, $2, 1, $3)
     ON CONFLICT (user_id, day) DO UPDATE SET uploads = user_daily_usage.uploads + 1, bytes = user_daily_usage.bytes + $3`,
    [user.id, today(), size],
  );
}
