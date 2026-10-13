-- Bring your own API keys: per-user provider keys (encrypted) and which key paid for a call.

-- CreateTable
CREATE TABLE "user_api_keys" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "provider" TEXT NOT NULL,
    "label" TEXT NOT NULL DEFAULT '',
    "key_enc" TEXT NOT NULL,
    "key_hint" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'untested',
    "last_checked_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_api_keys_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "user_api_keys_status_check" CHECK ("status" IN ('untested', 'valid', 'invalid', 'quota'))
);

-- CreateIndex
CREATE UNIQUE INDEX "user_api_keys_user_id_provider_key" ON "user_api_keys"("user_id", "provider");

-- AddForeignKey
ALTER TABLE "user_api_keys" ADD CONSTRAINT "user_api_keys_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AlterTable
ALTER TABLE "usage_events" ADD COLUMN "key_source" TEXT;

-- CreateIndex
CREATE INDEX "usage_events_user_id_key_source_ts_idx" ON "usage_events"("user_id", "key_source", "ts");
