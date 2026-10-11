import { readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { log } from "../util/logger.js";
import type { Db } from "./prisma.js";

/**
 * Schema changes are applied with `prisma migrate deploy` (part of `pnpm start`,
 * or `pnpm db:deploy`), never by the server itself. On connect the server only
 * compares prisma/migrations with _prisma_migrations and warns about gaps.
 */

async function migrationNames(): Promise<string[] | null> {
  const here = path.dirname(fileURLToPath(import.meta.url));
  // src/db and dist/db are both two levels below the backend root.
  const dir = path.join(here, "../../prisma/migrations");
  try {
    const entries = await readdir(dir, { withFileTypes: true });
    return entries.filter((e) => e.isDirectory()).map((e) => e.name).sort();
  } catch {
    return null;
  }
}

let warned = "";

export async function checkPendingMigrations(c: Db): Promise<void> {
  const local = await migrationNames();
  if (!local) return;
  let applied: Set<string>;
  try {
    const rows = await c.$queryRaw<Array<{ migration_name: string }>>`
      SELECT migration_name FROM _prisma_migrations WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL`;
    applied = new Set(rows.map((r) => r.migration_name));
  } catch (e) {
    if (/_prisma_migrations/.test((e as Error).message ?? "")) {
      log.error("database has no Prisma migration history: run `pnpm db:deploy` (or baseline an existing database, see docs/SPEC.md)");
      return;
    }
    throw e;
  }
  const pending = local.filter((m) => !applied.has(m));
  const key = pending.join(",");
  if (pending.length && key !== warned) log.error("pending database migrations, run `pnpm db:deploy`", { pending });
  warned = key;
}
