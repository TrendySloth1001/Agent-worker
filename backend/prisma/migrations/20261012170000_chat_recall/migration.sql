-- Cross-chat recall: a per-user semantic index of past conversations
-- (a separate table, so the knowledge base and its source types stay untouched),
-- a per-user on/off switch, and an "indexed" marker on conversations.

-- AlterTable
ALTER TABLE "users" ADD COLUMN "chat_recall_enabled" BOOLEAN NOT NULL DEFAULT true;

-- AlterTable
ALTER TABLE "conversations" ADD COLUMN "recall_indexed_at" TIMESTAMPTZ(6);

-- CreateTable
CREATE TABLE "conversation_chunks" (
    "id" BIGSERIAL NOT NULL,
    "conversation_id" UUID NOT NULL,
    "user_id" UUID,
    "ord" INTEGER NOT NULL,
    "kind" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "content_hash" TEXT NOT NULL,
    "embedding" vector(1024) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "conversation_chunks_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "conversation_chunks_kind_check" CHECK ("kind" IN ('header','turn'))
);

-- CreateIndex
CREATE UNIQUE INDEX "conversation_chunks_conversation_id_ord_key" ON "conversation_chunks"("conversation_id", "ord");
CREATE INDEX "conversation_chunks_user_idx" ON "conversation_chunks"("user_id");

-- Vector index (Prisma cannot model it)
CREATE INDEX "conversation_chunks_embedding_hnsw" ON "conversation_chunks" USING hnsw ("embedding" vector_cosine_ops) WITH (m = 16, ef_construction = 64);

-- AddForeignKey
ALTER TABLE "conversation_chunks" ADD CONSTRAINT "conversation_chunks_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
ALTER TABLE "conversation_chunks" ADD CONSTRAINT "conversation_chunks_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
