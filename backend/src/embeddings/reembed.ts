import { db, Prisma, tx } from "../db/prisma.js";
import { markEmbeddingsCurrent, needsReembed } from "../db/embeddingGuard.js";
import { toVector } from "../db/vector.js";
import { embeddingInput } from "../ingest/chunk.js";
import { log } from "../util/logger.js";
import { userCrypto } from "../crypto/userData.js";
import { embedTexts } from "./index.js";
import { dropAllIndexes } from "../recall/index.js";

const BATCH = 64;
let running = false;

/** Rebuilds every chunk vector with the configured model, then unlocks the knowledge base. */
export async function reembedAll(): Promise<void> {
  if (running || !needsReembed()) return;
  running = true;
  const started = Date.now();
  try {
    let lastId = 0n;
    let done = 0;
    for (;;) {
      const rows = await db().chunk.findMany({
        where: { id: { gt: lastId } },
        orderBy: { id: "asc" },
        take: BATCH,
        select: { id: true, headingPath: true, content: true, source: { select: { userId: true } } },
      });
      // Chunk text is sealed with the owner's key: open it just long enough to embed it.
      const opened = [];
      for (const r of rows) {
        const c = await userCrypto(r.source.userId);
        opened.push({ headingPath: r.headingPath === null ? null : c.open("chunks", "heading_path", r.headingPath), content: c.open("chunks", "content", r.content) });
      }
      if (rows.length === 0) break;
      const vectors = await embedTexts(
        opened.map((r) => embeddingInput(r)),
        "document",
        { reembed: true },
      );
      // Raw: vector column. One UPDATE ... FROM (VALUES ...) per batch.
      const values = rows.map((r, i) => Prisma.sql`(${r.id}::bigint, ${toVector(vectors[i])})`);
      await db().$executeRaw`
        UPDATE chunks c SET embedding = v.embedding::vector
        FROM (VALUES ${Prisma.join(values)}) AS v(id, embedding) WHERE c.id = v.id`;
      done += rows.length;
      lastId = rows[rows.length - 1].id;
    }
    // The chat recall index is derived data: vectors of the old model are dropped and rebuilt by the backfill.
    await dropAllIndexes();
    await tx((c) => markEmbeddingsCurrent(c));
    log.info("re-embedding finished", { chunks: done, ms: Date.now() - started });
  } catch (e) {
    log.error("re-embedding failed, will retry on next start", { message: (e as Error).message.slice(0, 160) });
  } finally {
    running = false;
  }
}
