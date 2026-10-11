import { query, withTx } from "../db/pool.js";
import { markEmbeddingsCurrent, needsReembed } from "../db/migrate.js";
import { embeddingInput } from "../ingest/chunk.js";
import { log } from "../util/logger.js";
import { embedTexts } from "./index.js";

const BATCH = 64;
let running = false;

/** Rebuilds every chunk vector with the configured model, then unlocks the knowledge base. */
export async function reembedAll(): Promise<void> {
  if (running || !needsReembed()) return;
  running = true;
  const started = Date.now();
  try {
    let lastId = 0;
    let done = 0;
    for (;;) {
      const { rows } = await query<{ id: string; heading_path: string | null; content: string }>(
        "SELECT id, heading_path, content FROM chunks WHERE id > $1 ORDER BY id LIMIT $2",
        [lastId, BATCH],
      );
      if (rows.length === 0) break;
      const vectors = await embedTexts(
        rows.map((r) => embeddingInput({ headingPath: r.heading_path, content: r.content })),
        "document",
        { reembed: true },
      );
      await query(
        `UPDATE chunks c SET embedding = v.embedding::vector
         FROM unnest($1::bigint[], $2::text[]) AS v(id, embedding) WHERE c.id = v.id`,
        [rows.map((r) => r.id), vectors.map((v) => `[${v.join(",")}]`)],
      );
      done += rows.length;
      lastId = Number(rows[rows.length - 1].id);
    }
    await withTx((c) => markEmbeddingsCurrent(c));
    log.info("re-embedding finished", { chunks: done, ms: Date.now() - started });
  } catch (e) {
    log.error("re-embedding failed, will retry on next start", { message: (e as Error).message.slice(0, 160) });
  } finally {
    running = false;
  }
}
