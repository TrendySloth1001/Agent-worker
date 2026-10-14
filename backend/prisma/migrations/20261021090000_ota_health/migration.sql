-- OTA v2 phase 1: per-attempt install outcome events and channel/device on the adoption row. Additive only.

ALTER TABLE "app_installs" ADD COLUMN "channel" TEXT NOT NULL DEFAULT 'stable';
ALTER TABLE "app_installs" ADD COLUMN "device_id" TEXT;

CREATE TABLE "app_install_events" (
    "id" BIGSERIAL NOT NULL,
    "user_id" UUID NOT NULL,
    "device_id" TEXT,
    "at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "build" INTEGER NOT NULL,
    "to_build" INTEGER NOT NULL,
    "patch_number" INTEGER,
    "stage" TEXT NOT NULL,
    "ok" BOOLEAN NOT NULL,
    "code" TEXT,
    "bytes" BIGINT,
    "via" TEXT NOT NULL DEFAULT 'full',

    CONSTRAINT "app_install_events_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "app_install_events_stage_check" CHECK ("stage" IN ('download_start', 'download_ok', 'download_fail', 'verify_fail', 'signature_mismatch', 'install_start', 'install_ok', 'install_fail', 'cancelled', 'first_launch_ok')),
    CONSTRAINT "app_install_events_via_check" CHECK ("via" IN ('full', 'delta', 'resume'))
);

CREATE INDEX "app_install_events_to_build_at_idx" ON "app_install_events"("to_build", "at");

ALTER TABLE "app_install_events" ADD CONSTRAINT "app_install_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
