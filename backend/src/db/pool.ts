import pg from "pg";
import { config } from "../config.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { runMigrations } from "./migrate.js";

let pool: pg.Pool | null = null;
let up = false;
let closed = false;
let retryTimer: NodeJS.Timeout | null = null;
let connecting = false;
const upHooks: Array<() => void> = [];

/** Run cb every time the DB becomes reachable (and now, if it already is). */
export function onDbUp(cb: () => void): void {
  upHooks.push(cb);
  if (up) cb();
}

export function isDbUp(): boolean {
  return up;
}

function markDown(reason: string) {
  if (up) log.warn("database down", { reason: reason.slice(0, 120) });
  up = false;
  scheduleRetry();
}

function scheduleRetry() {
  if (closed || retryTimer || connecting) return;
  retryTimer = setTimeout(() => {
    retryTimer = null;
    void connect();
  }, 10_000);
  retryTimer.unref();
}

async function connect() {
  if (closed || connecting || !config.databaseUrl) return;
  connecting = true;
  try {
    if (!pool) {
      pool = new pg.Pool({ connectionString: config.databaseUrl, max: 8, connectionTimeoutMillis: 5000 });
      pool.on("error", (e) => markDown(e.message));
    }
    await pool.query("SELECT 1");
    await runMigrations(pool);
    const wasUp = up;
    if (!up) log.info("database ready");
    up = true;
    if (!wasUp) for (const cb of upHooks) { try { cb(); } catch { /* hook errors are not fatal */ } }
  } catch (e) {
    up = false;
    log.warn("database unavailable, retrying in 10s", { reason: (e as Error).message.slice(0, 120) });
  } finally {
    connecting = false;
    if (!up) scheduleRetry();
  }
}

/** Non-blocking, never throws. */
export function initDb(): void {
  closed = false;
  if (!config.databaseUrl) {
    log.warn("DATABASE_URL not set, knowledge base disabled");
    return;
  }
  void connect();
}

export function getPool(): pg.Pool {
  if (!pool || !up) throw new AppError(503, "unavailable", "Database unavailable", true);
  return pool;
}

function isConnError(e: unknown): boolean {
  const code = (e as { code?: string }).code ?? "";
  return /^(ECONN|ETIMEDOUT|ENOTFOUND|57P0|08)/.test(code) || /Connection terminated|timeout exceeded/i.test((e as Error).message ?? "");
}

export async function query<T = any>(text: string, params?: unknown[]): Promise<{ rows: T[]; rowCount: number }> {
  const p = getPool();
  try {
    const r = await p.query(text, params as any[]);
    return { rows: r.rows as T[], rowCount: r.rowCount ?? 0 };
  } catch (e) {
    if (isConnError(e)) {
      markDown((e as Error).message);
      throw new AppError(503, "unavailable", "Database unavailable", true);
    }
    throw e;
  }
}

/** Runs fn inside a transaction on a dedicated client. */
export async function withTx<T>(fn: (c: pg.PoolClient) => Promise<T>): Promise<T> {
  const p = getPool();
  let client: pg.PoolClient;
  try {
    client = await p.connect();
  } catch (e) {
    markDown((e as Error).message);
    throw new AppError(503, "unavailable", "Database unavailable", true);
  }
  try {
    await client.query("BEGIN");
    const out = await fn(client);
    await client.query("COMMIT");
    return out;
  } catch (e) {
    await client.query("ROLLBACK").catch(() => {});
    if (isConnError(e)) {
      markDown((e as Error).message);
      throw new AppError(503, "unavailable", "Database unavailable", true);
    }
    throw e;
  } finally {
    client.release();
  }
}

export async function closeDb(): Promise<void> {
  closed = true;
  if (retryTimer) clearTimeout(retryTimer);
  retryTimer = null;
  up = false;
  const p = pool;
  pool = null;
  await p?.end().catch(() => {});
}
