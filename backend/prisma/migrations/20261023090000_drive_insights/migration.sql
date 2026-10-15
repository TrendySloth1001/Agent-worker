-- Sealed sparky-view readings of Google Drive files. Additive: one new table.
CREATE TABLE "drive_insights" (
    "user_id" UUID NOT NULL,
    "file_id" TEXT NOT NULL,
    "modified_time" TEXT NOT NULL,
    "sealed" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "drive_insights_pkey" PRIMARY KEY ("user_id", "file_id"),
    CONSTRAINT "drive_insights_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION
);
