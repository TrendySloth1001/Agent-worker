-- Generated docs and uploaded files are indexed into the knowledge base as
-- sources of type 'doc' / 'file' (one source per doc/file, one document per
-- doc section).
ALTER TABLE "sources" DROP CONSTRAINT IF EXISTS "sources_type_check";
ALTER TABLE "sources" ADD CONSTRAINT "sources_type_check"
  CHECK (type IN ('web','github','stackoverflow','reddit','hackernews','note','file','doc'));

-- Retrieval indexes (already created by the init migration; kept idempotent so
-- a database that lost them is repaired on deploy).
CREATE INDEX IF NOT EXISTS "chunks_embedding_hnsw" ON "chunks" USING hnsw ("embedding" vector_cosine_ops) WITH (m = 16, ef_construction = 64);
CREATE INDEX IF NOT EXISTS "chunks_tsv_gin" ON "chunks" USING GIN ("tsv");
CREATE INDEX IF NOT EXISTS "chunks_source_idx" ON "chunks" ("source_id");
