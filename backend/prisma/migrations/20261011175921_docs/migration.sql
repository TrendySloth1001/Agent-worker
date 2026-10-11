-- AlterTable
ALTER TABLE "user_daily_usage" ADD COLUMN     "docs" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "docs" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "conversation_id" UUID,
    "title" TEXT NOT NULL DEFAULT '',
    "prompt" TEXT NOT NULL,
    "options" JSONB NOT NULL DEFAULT '{}',
    "status" TEXT NOT NULL DEFAULT 'planning',
    "outline" JSONB NOT NULL DEFAULT '{}',
    "glossary" JSONB NOT NULL DEFAULT '[]',
    "sources" JSONB NOT NULL DEFAULT '[]',
    "summary" TEXT NOT NULL DEFAULT '',
    "words" INTEGER NOT NULL DEFAULT 0,
    "version" INTEGER NOT NULL DEFAULT 1,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "docs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "doc_sections" (
    "doc_id" UUID NOT NULL,
    "section_id" TEXT NOT NULL,
    "ord" INTEGER NOT NULL,
    "heading" TEXT NOT NULL,
    "level" INTEGER NOT NULL DEFAULT 2,
    "markdown" TEXT NOT NULL DEFAULT '',
    "summary" TEXT NOT NULL DEFAULT '',
    "status" TEXT NOT NULL DEFAULT 'pending',
    "source_ids" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "used_ids" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "evidence" JSONB NOT NULL DEFAULT '[]',
    "images" JSONB NOT NULL DEFAULT '[]',
    "model" TEXT,
    "words" INTEGER NOT NULL DEFAULT 0,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "doc_sections_pkey" PRIMARY KEY ("doc_id","section_id")
);

-- CreateTable
CREATE TABLE "doc_revisions" (
    "id" BIGSERIAL NOT NULL,
    "doc_id" UUID NOT NULL,
    "section_id" TEXT NOT NULL,
    "version" INTEGER NOT NULL,
    "markdown" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "doc_revisions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "doc_highlights" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "doc_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "section_id" TEXT NOT NULL,
    "quote" TEXT NOT NULL,
    "prefix" TEXT NOT NULL DEFAULT '',
    "suffix" TEXT NOT NULL DEFAULT '',
    "color" TEXT NOT NULL DEFAULT 'yellow',
    "note" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "doc_highlights_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "docs_user_id_updated_at_idx" ON "docs"("user_id", "updated_at" DESC);

-- CreateIndex
CREATE INDEX "docs_conversation_id_idx" ON "docs"("conversation_id");

-- CreateIndex
CREATE INDEX "doc_revisions_doc_id_section_id_created_at_idx" ON "doc_revisions"("doc_id", "section_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "doc_highlights_doc_id_idx" ON "doc_highlights"("doc_id");

-- AddForeignKey
ALTER TABLE "docs" ADD CONSTRAINT "docs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "docs" ADD CONSTRAINT "docs_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "doc_sections" ADD CONSTRAINT "doc_sections_doc_id_fkey" FOREIGN KEY ("doc_id") REFERENCES "docs"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "doc_revisions" ADD CONSTRAINT "doc_revisions_doc_id_fkey" FOREIGN KEY ("doc_id") REFERENCES "docs"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "doc_highlights" ADD CONSTRAINT "doc_highlights_doc_id_fkey" FOREIGN KEY ("doc_id") REFERENCES "docs"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- CHECK constraints (not representable in schema.prisma)
ALTER TABLE "docs" ADD CONSTRAINT "docs_status_check" CHECK ("status" IN ('planning','outline_ready','researching','writing','done','partial','failed','interrupted'));
ALTER TABLE "doc_sections" ADD CONSTRAINT "doc_sections_status_check" CHECK ("status" IN ('pending','writing','done','failed'));
ALTER TABLE "doc_revisions" ADD CONSTRAINT "doc_revisions_reason_check" CHECK ("reason" IN ('generate','regenerate','expand','shorten','simplify','edit','custom'));
