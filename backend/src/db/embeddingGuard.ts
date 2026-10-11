import { config } from "../config.js";
import { log } from "../util/logger.js";
import type { Db, Tx } from "./prisma.js";

/**
 * Startup check that the stored vectors match the configured embedding model
 * (kb_meta). Formerly part of the pre-Prisma SQL migration runner.
 */

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

const wanted = () => ({ embedding_model: config.embeddingModel, embedding_dimensions: String(config.embeddingDimensions) });

async function writeMeta(c: Db | Tx): Promise<void> {
  for (const [key, value] of Object.entries(wanted())) {
    await c.kbMeta.upsert({ where: { key }, create: { key, value }, update: { value } });
  }
}

/** Called once every chunk has been re-embedded with the configured model. */
export async function markEmbeddingsCurrent(c: Db | Tx): Promise<void> {
  await writeMeta(c);
  guardError = null;
  reembedNeeded = false;
}

/** Runs every time the database becomes reachable. */
export async function checkEmbeddingMeta(c: Db): Promise<void> {
  const rows = await c.kbMeta.findMany({ where: { key: { in: ["embedding_model", "embedding_dimensions"] } } });
  const meta = Object.fromEntries(rows.map((r) => [r.key, r.value])) as Record<string, string>;
  const want = wanted();
  const same = meta.embedding_model === want.embedding_model && meta.embedding_dimensions === want.embedding_dimensions;
  if (same) {
    guardError = null;
    return;
  }
  const chunkCount = await c.chunk.count();
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
  await writeMeta(c);
  guardError = null;
}
