-- CreateTable
CREATE TABLE "github_oauth_flows" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "state_hash" TEXT NOT NULL,
    "code_verifier" TEXT NOT NULL,
    "mode" TEXT NOT NULL,
    "user_id" UUID,
    "device" TEXT,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "ticket_hash" TEXT,
    "ticket_expires_at" TIMESTAMPTZ(6),
    "result" JSONB,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "github_oauth_flows_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "github_oauth_flows_state_hash_key" ON "github_oauth_flows"("state_hash");

-- CreateIndex
CREATE UNIQUE INDEX "github_oauth_flows_ticket_hash_key" ON "github_oauth_flows"("ticket_hash");

-- CreateIndex
CREATE INDEX "github_oauth_flows_created_at_idx" ON "github_oauth_flows"("created_at");

-- AddForeignKey
ALTER TABLE "github_oauth_flows" ADD CONSTRAINT "github_oauth_flows_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- Not representable in schema.prisma (see the model's doc comment).
ALTER TABLE "github_oauth_flows" ADD CONSTRAINT "github_oauth_flows_mode_check" CHECK (mode IN ('signin','connect','link'));
ALTER TABLE "github_oauth_flows" ADD CONSTRAINT "github_oauth_flows_status_check" CHECK (status IN ('pending','exchanging','ready','redeemed','failed'));
