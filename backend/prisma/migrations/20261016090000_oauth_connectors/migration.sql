-- Generic OAuth connectors (Google Drive, Notion): account details on
-- connections, a provider-agnostic flow table, and two new knowledge-base
-- source types.

-- AlterTable
ALTER TABLE "connections" ADD COLUMN "account_name" TEXT;
ALTER TABLE "connections" ADD COLUMN "account_email" TEXT;
ALTER TABLE "connections" ADD COLUMN "meta" JSONB NOT NULL DEFAULT '{}';
ALTER TABLE "connections" ADD COLUMN "needs_reauth" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "oauth_flows" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "provider" TEXT NOT NULL,
    "mode" TEXT NOT NULL DEFAULT 'connect',
    "state_hash" TEXT NOT NULL,
    "code_verifier" TEXT NOT NULL,
    "user_id" UUID NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "ticket_hash" TEXT,
    "ticket_expires_at" TIMESTAMPTZ(6),
    "result" JSONB,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "oauth_flows_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "oauth_flows_state_hash_key" ON "oauth_flows"("state_hash");
CREATE UNIQUE INDEX "oauth_flows_ticket_hash_key" ON "oauth_flows"("ticket_hash");
CREATE INDEX "oauth_flows_created_at_idx" ON "oauth_flows"("created_at");

-- AddForeignKey
ALTER TABLE "oauth_flows" ADD CONSTRAINT "oauth_flows_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- Not representable in schema.prisma.
ALTER TABLE "oauth_flows" ADD CONSTRAINT "oauth_flows_mode_check" CHECK (mode IN ('connect','picker'));
ALTER TABLE "sources" DROP CONSTRAINT IF EXISTS "sources_type_check";
ALTER TABLE "sources" ADD CONSTRAINT "sources_type_check"
  CHECK (type IN ('web','github','stackoverflow','reddit','hackernews','note','file','doc','google_drive','notion'));
