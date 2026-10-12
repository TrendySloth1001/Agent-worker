-- Search indexes for conversation / message / file-name search (typo tolerance + stemming).
-- Idempotent and safe on existing data. Not CONCURRENTLY: Prisma runs each
-- migration in a transaction, where CREATE INDEX CONCURRENTLY is not allowed.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Substring (ILIKE) and typo (word_similarity <%) search on titles, message text and file names.
CREATE INDEX IF NOT EXISTS "conversations_title_trgm" ON "conversations" USING GIN ("title" gin_trgm_ops);
CREATE INDEX IF NOT EXISTS "conversation_messages_content_trgm" ON "conversation_messages" USING GIN ("content" gin_trgm_ops);
CREATE INDEX IF NOT EXISTS "files_name_trgm" ON "files" USING GIN ("name" gin_trgm_ops);

-- Stemmed full-text search over message text. An expression index (no stored column, so no table
-- rewrite); left() keeps a very long message under tsvector's 1MB limit. Queries must use the same expression.
CREATE INDEX IF NOT EXISTS "conversation_messages_content_fts"
  ON "conversation_messages" USING GIN ((to_tsvector('english'::regconfig, left("content", 100000))));

-- RAG typo fallback: `term <% content` over knowledge-base chunks.
CREATE INDEX IF NOT EXISTS "chunks_content_trgm" ON "chunks" USING GIN ("content" gin_trgm_ops);
