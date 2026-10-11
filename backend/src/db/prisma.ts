import pg from "pg";
import { PrismaPg } from "@prisma/adapter-pg";
import { Prisma, PrismaClient } from "../generated/prisma/client.js";
import { config } from "../config.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { checkEmbeddingMeta } from "./embeddingGuard.js";
import { checkPendingMigrations } from "./migrations.js";

/**
 * The one PrismaClient of the process, plus the database up/down state.
 *
 * Prisma 7 talks to Postgres through a driver adapter; we hand it our own
 * `pg.Pool` so idle-connection errors are observed (an unhandled pool 'error'
 * would crash the process) and mark the database down. Every operation,
 * including $queryRaw/$executeRaw, runs through an extension that turns
 * connection failures into a retryable 503, like the old pg wrapper did.
 */

function isConnError(e: unknown): boolean {
  const err = e as { code?: string; message?: string; cause?: { code?: string; kind?: string; originalCode?: string } };
  const code = String(err?.code ?? err?.cause?.originalCode ?? err?.cause?.code ?? "");
  if (/^(P1001|P1002|P1008|P1017|P2024)$/.test(code)) return true;
  if (/^(ECONN|ETIMEDOUT|ENOTFOUND|57P0|08)/.test(code)) return true;
  if (err?.cause?.kind && /DatabaseNotReachable|ConnectionClosed|SocketTimeout|TooManyConnections/.test(err.cause.kind)) return true;
  return /Connection terminated|timeout exceeded|ECONNREFUSED|ECONNRESET|Can't reach database|server closed the connection/i.test(err?.message ?? "");
}

const unavailable = () => new AppError(503, "unavailable", "Database unavailable", true);

function mapError(e: unknown): unknown {
  if (e instanceof AppError) return e;
  if (isConnError(e)) {
    markDown((e as Error).message ?? String(e));
    return unavailable();
  }
  return e;
}

function createClient(pool: pg.Pool) {
  return new PrismaClient({ adapter: new PrismaPg(pool) }).$extends({
    name: "connection-errors",
    query: {
      async $allOperations({ args, query }) {
        try {
          return await query(args);
        } catch (e) {
          throw mapError(e);
        }
      },
    },
  });
}

export type Db = ReturnType<typeof createClient>;
/** The client handed to `$transaction(async (tx) => ...)` callbacks. */
export type Tx = Parameters<Parameters<Db["$transaction"]>[0]>[0];

let pool: pg.Pool | null = null;
let client: Db | null = null;
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
    if (!pool || !client) {
      pool = new pg.Pool({ connectionString: config.databaseUrl, max: 8, connectionTimeoutMillis: 5000 });
      pool.on("error", (e) => markDown(e.message));
      client = createClient(pool);
    }
    await client.$queryRaw`SELECT 1`;
    // Schema changes are applied by `prisma migrate deploy` (see docs/SPEC.md); here we only warn.
    await checkPendingMigrations(client);
    await checkEmbeddingMeta(client);
    const wasUp = up;
    if (!up) log.info("database ready");
    up = true;
    if (!wasUp) for (const cb of upHooks) { try { cb(); } catch { /* hook errors are not fatal */ } }
  } catch (e) {
    up = false;
    log.warn("database unavailable, retrying in 10s", { reason: ((e as Error).message ?? String(e)).slice(0, 120) });
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

/** The PrismaClient; a retryable 503 while the database is unreachable. */
export function db(): Db {
  if (!client || !up) throw unavailable();
  return client;
}

/** Runs fn with the client; a down database becomes a rejected promise (safe in `.catch()` chains). */
export async function withDb<T>(fn: (c: Db) => Promise<T>): Promise<T> {
  return fn(db());
}

/** Interactive transaction (replaces the old withTx); connection failures become 503. */
export async function tx<T>(fn: (t: Tx) => Promise<T>, options?: { timeout?: number; maxWait?: number }): Promise<T> {
  try {
    return await db().$transaction(fn, { timeout: options?.timeout ?? 15_000, maxWait: options?.maxWait ?? 5_000 });
  } catch (e) {
    throw mapError(e);
  }
}

export async function closeDb(): Promise<void> {
  closed = true;
  if (retryTimer) clearTimeout(retryTimer);
  retryTimer = null;
  up = false;
  const c = client;
  const p = pool;
  client = null;
  pool = null;
  await c?.$disconnect().catch(() => {});
  await p?.end().catch(() => {});
}

export { Prisma };
