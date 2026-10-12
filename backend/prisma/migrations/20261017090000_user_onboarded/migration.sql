-- First-run tour: when the user finished or skipped it. Accounts that exist
-- before this migration already know the app, so they count as onboarded.

-- AlterTable
ALTER TABLE "users" ADD COLUMN "onboarded_at" TIMESTAMPTZ(6);

-- Backfill
UPDATE "users" SET "onboarded_at" = "created_at" WHERE "onboarded_at" IS NULL;
