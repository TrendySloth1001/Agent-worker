import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import type pg from "pg";
import { config } from "../config.js";
import { log } from "../util/logger.js";

let guardError: string | null = null;
let reembedNeeded = false;

/** Non-null when the configured embedding model/dims differ from what the KB was built with. */
export function getEmbeddingGuardError(): string | null {
  return guardError;
}

/** True when stored vectors came from a different embedding model and must be rebuilt. */
export function needsReembed(): boolean {
  return reembedNeeded;
}

/** Called once every chunk has been re-embedded with the configured model. */
export async function markEmbeddingsCurrent(client: { query: pg.PoolClient["query"] }): Promise<void> {
  const want = { embedding_model: config.embeddingModel, embedding_dimensions: String(config.embeddingDimensions) };
  for (const [k, v] of Object.entries(want)) {
    await client.query("INSERT INTO kb_meta(key, value) VALUES ($1,$2) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value", [k, v]);
  }
  guardError = null;
  reembedNeeded = false;
}

async function sqlDir(): Promise<string> {
  const here = path.dirname(fileURLToPath(import.meta.url));
  for (const dir of [path.join(here, "sql"), path.join(here, "../../src/db/sql")]) {
    try {
      await readdir(dir);
      return dir;
    } catch {
      /* try next */
    }
  }
  throw new Error("migrations directory not found");
}

export async function runMigrations(pool: pg.Pool): Promise<void> {
  const client = await pool.connect();
  try {
    // advisory lock so concurrent boots do not race
    await client.query("SELECT pg_advisory_lock(727001)");
    await client.query(
      "CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())",
    );
    const dir = await sqlDir();
    const files = (await readdir(dir)).filter((f) => f.endsWith(".sql")).sort();
    const done = new Set((await client.query("SELECT name FROM schema_migrations")).rows.map((r) => r.name as string));
    for (const f of files) {
      if (done.has(f)) continue;
      const sql = await readFile(path.join(dir, f), "utf8");
      try {
        await client.query("BEGIN");
        await client.query(sql);
        await client.query("INSERT INTO schema_migrations(name) VALUES ($1)", [f]);
        await client.query("COMMIT");
        log.info("migration applied", { name: f });
      } catch (e) {
        await client.query("ROLLBACK").catch(() => {});
        throw e;
      }
    }
    await checkEmbeddingMeta(client);
  } finally {
    await client.query("SELECT pg_advisory_unlock(727001)").catch(() => {});
    client.release();
  }
}

async function checkEmbeddingMeta(client: pg.PoolClient) {
  const rows = (await client.query("SELECT key, value FROM kb_meta WHERE key IN ('embedding_model','embedding_dimensions')")).rows;
  const meta = Object.fromEntries(rows.map((r) => [r.key, r.value])) as Record<string, string>;
  const want = { embedding_model: config.embeddingModel, embedding_dimensions: String(config.embeddingDimensions) };
  const same = meta.embedding_model === want.embedding_model && meta.embedding_dimensions === want.embedding_dimensions;
  if (same) {
    guardError = null;
    return;
  }
  const chunkCount = Number((await client.query("SELECT count(*)::int AS n FROM chunks")).rows[0].n);
  if (meta.embedding_model && chunkCount > 0) {
    if (meta.embedding_dimensions !== want.embedding_dimensions) {
      guardError = `Embedding dimensions changed (${meta.embedding_dimensions} -> ${want.embedding_dimensions}). Drop the knowledge base and re-ingest.`;
      log.error(guardError);
      return;
    }
    // Same size, different model: rebuild the vectors in place.
    guardError = `Re-embedding the knowledge base for ${want.embedding_model}`;
    reembedNeeded = true;
    log.warn("embedding model changed, re-embedding", { from: meta.embedding_model, to: want.embedding_model, chunks: chunkCount });
    return;
  }
  for (const [k, v] of Object.entries(want)) {
    await client.query("INSERT INTO kb_meta(key, value) VALUES ($1,$2) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value", [k, v]);
  }
  guardError = null;
}
