-- Baseline of the schema built by the pre-Prisma SQL runner (src/db/sql/001..010).
-- Generated with `prisma migrate diff --from-empty --to-schema prisma/schema.prisma --script`,
-- then completed by hand with what Prisma cannot express (extensions, NOT NULL
-- arrays, the generated tsv column, HNSW indexes, CHECK constraints, the
-- expression index, UNIQUE NULLS NOT DISTINCT, unique constraints instead of
-- unique indexes). On existing databases it is only marked as applied:
--   prisma migrate resolve --applied 0_init
-- On an empty database `prisma migrate deploy` runs it and yields the same schema.

-- Extensions
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS citext;

-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "email" CITEXT NOT NULL,
    "password_hash" TEXT NOT NULL,
    "name" TEXT NOT NULL DEFAULT '',
    "avatar_url" TEXT,
    "role" TEXT NOT NULL DEFAULT 'user',
    "limits" JSONB NOT NULL DEFAULT '{}',
    "disabled" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "last_login_at" TIMESTAMPTZ,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "auth_sessions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "family_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "token_hash" TEXT NOT NULL,
    "device" TEXT,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "family_created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "expires_at" TIMESTAMPTZ NOT NULL,
    "revoked_at" TIMESTAMPTZ,
    "replaced_by" UUID,

    CONSTRAINT "auth_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_daily_usage" (
    "user_id" UUID NOT NULL,
    "day" DATE NOT NULL,
    "chats" INTEGER NOT NULL DEFAULT 0,
    "tables" INTEGER NOT NULL DEFAULT 0,
    "uploads" INTEGER NOT NULL DEFAULT 0,
    "bytes" BIGINT NOT NULL DEFAULT 0,

    CONSTRAINT "user_daily_usage_pkey" PRIMARY KEY ("user_id","day")
);

-- CreateTable
CREATE TABLE "conversations" (
    "id" UUID NOT NULL,
    "title" TEXT,
    "title_source" TEXT,
    "message_count" INTEGER NOT NULL DEFAULT 0,
    "preview" TEXT,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "pinned_at" TIMESTAMPTZ,
    "archived_at" TIMESTAMPTZ,
    "origin" TEXT,
    "forked_from" UUID,
    "fork_point" INTEGER,
    "merged_from" UUID[] NOT NULL DEFAULT '{}',
    "user_id" UUID,

    CONSTRAINT "conversations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "conversation_messages" (
    "conversation_id" UUID NOT NULL,
    "position" INTEGER NOT NULL,
    "role" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "model" TEXT,
    "citations" JSONB NOT NULL DEFAULT '[]',
    "used_ids" TEXT[] NOT NULL DEFAULT '{}',
    "is_error" BOOLEAN NOT NULL DEFAULT false,
    "images" JSONB NOT NULL DEFAULT '[]',
    "evidence" JSONB NOT NULL DEFAULT '[]',
    "attachments" JSONB NOT NULL DEFAULT '[]',
    "meta" JSONB NOT NULL DEFAULT '{}',
    "table" JSONB,

    CONSTRAINT "conversation_messages_pkey" PRIMARY KEY ("conversation_id","position")
);

-- CreateTable
CREATE TABLE "files" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "conversation_id" UUID,
    "name" TEXT NOT NULL,
    "mime" TEXT NOT NULL,
    "size" BIGINT NOT NULL,
    "kind" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'processing',
    "error" TEXT,
    "s3_key" TEXT NOT NULL,
    "thumb_key" TEXT,
    "meta" JSONB NOT NULL DEFAULT '{}',
    "text" TEXT,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "user_id" UUID,

    CONSTRAINT "files_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "file_chunks" (
    "id" BIGSERIAL NOT NULL,
    "file_id" UUID NOT NULL,
    "ord" INTEGER NOT NULL,
    "content" TEXT NOT NULL,
    "embedding" vector(1024) NOT NULL,

    CONSTRAINT "file_chunks_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sources" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "type" TEXT NOT NULL,
    "uri" TEXT NOT NULL,
    "title" TEXT,
    "status" TEXT NOT NULL DEFAULT 'queued',
    "options" JSONB NOT NULL DEFAULT '{}',
    "error" TEXT,
    "progress_done" INTEGER NOT NULL DEFAULT 0,
    "progress_total" INTEGER,
    "doc_count" INTEGER NOT NULL DEFAULT 0,
    "chunk_count" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "last_ingested_at" TIMESTAMPTZ,
    "user_id" UUID,

    CONSTRAINT "sources_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "documents" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "source_id" UUID NOT NULL,
    "url" TEXT NOT NULL,
    "title" TEXT,
    "content_hash" TEXT,
    "meta" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT "documents_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "chunks" (
    "id" BIGSERIAL NOT NULL,
    "document_id" UUID NOT NULL,
    "source_id" UUID NOT NULL,
    "ord" INTEGER NOT NULL,
    "heading_path" TEXT,
    "content" TEXT NOT NULL,
    "token_count" INTEGER,
    "content_hash" TEXT NOT NULL,
    "embedding" vector(1024) NOT NULL,
    "tsv" tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, content)) STORED,

    CONSTRAINT "chunks_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "kb_meta" (
    "key" TEXT NOT NULL,
    "value" TEXT NOT NULL,

    CONSTRAINT "kb_meta_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "usage_events" (
    "id" BIGSERIAL NOT NULL,
    "ts" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "provider" TEXT NOT NULL,
    "model" TEXT,
    "kind" TEXT NOT NULL,
    "ok" BOOLEAN NOT NULL,
    "status" INTEGER,
    "latency_ms" INTEGER,
    "count" INTEGER NOT NULL DEFAULT 1,
    "prompt_tokens" INTEGER,
    "completion_tokens" INTEGER,

    CONSTRAINT "usage_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "schema_migrations" (
    "name" TEXT NOT NULL,
    "applied_at" TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT "schema_migrations_pkey" PRIMARY KEY ("name")
);

-- CreateIndex
ALTER TABLE "users" ADD CONSTRAINT "users_email_key" UNIQUE ("email");

-- CreateIndex (at most one owner)
CREATE UNIQUE INDEX "users_one_owner" ON "users"("role") WHERE (role = 'owner'::text);

-- CreateIndex
ALTER TABLE "auth_sessions" ADD CONSTRAINT "auth_sessions_token_hash_key" UNIQUE ("token_hash");

-- CreateIndex
CREATE INDEX "auth_sessions_family_idx" ON "auth_sessions"("family_id");

-- CreateIndex
CREATE INDEX "auth_sessions_user_idx" ON "auth_sessions"("user_id");

-- CreateIndex
CREATE INDEX "conversations_forked_from_idx" ON "conversations"("forked_from");

-- CreateIndex
CREATE INDEX "conversations_updated_idx" ON "conversations"("updated_at" DESC);

-- CreateIndex
CREATE INDEX "conversations_user_idx" ON "conversations"("user_id", "updated_at" DESC);

-- CreateIndex
CREATE INDEX "files_conversation_idx" ON "files"("conversation_id");

-- CreateIndex
CREATE INDEX "files_user_idx" ON "files"("user_id");

-- CreateIndex
CREATE INDEX "file_chunks_embedding_hnsw" ON "file_chunks" USING hnsw ("embedding" vector_cosine_ops) WITH (m = 16, ef_construction = 64);

-- CreateIndex
ALTER TABLE "file_chunks" ADD CONSTRAINT "file_chunks_file_id_ord_key" UNIQUE ("file_id", "ord");

-- CreateIndex
CREATE INDEX "sources_user_idx" ON "sources"("user_id");

-- CreateIndex
-- The same URL may be ingested by different users; NULL owners compare equal.
ALTER TABLE "sources" ADD CONSTRAINT "sources_user_type_uri_key" UNIQUE NULLS NOT DISTINCT ("user_id", "type", "uri");

-- CreateIndex
CREATE INDEX "documents_source_idx" ON "documents"("source_id");

-- CreateIndex
ALTER TABLE "documents" ADD CONSTRAINT "documents_source_id_url_key" UNIQUE ("source_id", "url");

-- CreateIndex
CREATE INDEX "chunks_embedding_hnsw" ON "chunks" USING hnsw ("embedding" vector_cosine_ops) WITH (m = 16, ef_construction = 64);

-- CreateIndex
CREATE INDEX "chunks_source_idx" ON "chunks"("source_id");

-- CreateIndex
CREATE INDEX "chunks_tsv_gin" ON "chunks" USING GIN ("tsv");

-- CreateIndex
ALTER TABLE "chunks" ADD CONSTRAINT "chunks_document_id_ord_key" UNIQUE ("document_id", "ord");

-- CreateIndex
CREATE INDEX "usage_events_provider_ts_idx" ON "usage_events"("provider", "ts");

-- CreateIndex
CREATE INDEX "usage_events_ts_idx" ON "usage_events"("ts");

-- AddForeignKey
ALTER TABLE "auth_sessions" ADD CONSTRAINT "auth_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "user_daily_usage" ADD CONSTRAINT "user_daily_usage_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "conversations" ADD CONSTRAINT "conversations_forked_from_fkey" FOREIGN KEY ("forked_from") REFERENCES "conversations"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "conversations" ADD CONSTRAINT "conversations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "conversation_messages" ADD CONSTRAINT "conversation_messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "files" ADD CONSTRAINT "files_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "file_chunks" ADD CONSTRAINT "file_chunks_file_id_fkey" FOREIGN KEY ("file_id") REFERENCES "files"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sources" ADD CONSTRAINT "sources_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "documents" ADD CONSTRAINT "documents_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "sources"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "chunks" ADD CONSTRAINT "chunks_document_id_fkey" FOREIGN KEY ("document_id") REFERENCES "documents"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "chunks" ADD CONSTRAINT "chunks_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "sources"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- Expression index for the conversation list (pinned first, archived apart)
CREATE INDEX "conversations_list_idx" ON "conversations" ((archived_at IS NULL), (pinned_at IS NOT NULL) DESC, updated_at DESC);

-- CHECK constraints (not representable in schema.prisma)
ALTER TABLE "users" ADD CONSTRAINT "users_role_check" CHECK (role IN ('owner','user'));
ALTER TABLE "conversations" ADD CONSTRAINT "conversations_title_source_check" CHECK (title_source IN ('ai','fallback','user','derived'));
ALTER TABLE "conversations" ADD CONSTRAINT "conversations_origin_check" CHECK (origin IN ('fork','merge'));
ALTER TABLE "conversation_messages" ADD CONSTRAINT "conversation_messages_role_check" CHECK (role IN ('user','assistant','context'));
ALTER TABLE "files" ADD CONSTRAINT "files_kind_check" CHECK (kind IN ('image','document','video','audio'));
ALTER TABLE "files" ADD CONSTRAINT "files_status_check" CHECK (status IN ('processing','ready','failed'));
ALTER TABLE "sources" ADD CONSTRAINT "sources_type_check" CHECK (type IN ('web','github','stackoverflow','reddit','hackernews','note'));
ALTER TABLE "sources" ADD CONSTRAINT "sources_status_check" CHECK (status IN ('queued','running','ready','failed'));
ALTER TABLE "usage_events" ADD CONSTRAINT "usage_events_kind_check" CHECK (kind IN ('chat','embed','search','fetch','transcribe'));
