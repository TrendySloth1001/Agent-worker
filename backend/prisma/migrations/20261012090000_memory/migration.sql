-- Long-term memory: per-user memories with pgvector embeddings, a per-user
-- on/off switch, and a rolling summary on conversations.

-- AlterTable
ALTER TABLE "users" ADD COLUMN "memory_enabled" BOOLEAN NOT NULL DEFAULT true;

-- AlterTable
ALTER TABLE "conversations"
    ADD COLUMN "summary" TEXT,
    ADD COLUMN "summary_upto" INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN "summary_hash" TEXT;

-- CreateTable
CREATE TABLE "memories" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "text" TEXT NOT NULL,
    "kind" TEXT NOT NULL DEFAULT 'fact',
    "embedding" vector(1024),
    "source_conversation_id" UUID,
    "pinned" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_used_at" TIMESTAMPTZ(6),

    CONSTRAINT "memories_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "memories_kind_check" CHECK ("kind" IN ('fact','preference','project','instruction'))
);

-- CreateIndex
CREATE INDEX "memories_user_id_updated_at_idx" ON "memories"("user_id", "updated_at" DESC);

-- Vector index (Prisma cannot model it)
CREATE INDEX "memories_embedding_hnsw" ON "memories" USING hnsw ("embedding" vector_cosine_ops) WITH (m = 16, ef_construction = 64);

-- AddForeignKey
ALTER TABLE "memories" ADD CONSTRAINT "memories_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
