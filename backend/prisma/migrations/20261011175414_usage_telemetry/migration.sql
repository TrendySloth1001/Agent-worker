-- AlterTable
ALTER TABLE "usage_events" ADD COLUMN     "attempt" INTEGER,
ADD COLUMN     "conversation_id" TEXT,
ADD COLUMN     "error_code" TEXT,
ADD COLUMN     "error_message" TEXT,
ADD COLUMN     "purpose" TEXT,
ADD COLUMN     "request_id" TEXT,
ADD COLUMN     "ttft_ms" INTEGER,
ADD COLUMN     "user_id" UUID;

-- CreateIndex
CREATE INDEX "usage_events_model_ts_idx" ON "usage_events"("model", "ts");

-- CreateIndex
CREATE INDEX "usage_events_user_id_ts_idx" ON "usage_events"("user_id", "ts");
