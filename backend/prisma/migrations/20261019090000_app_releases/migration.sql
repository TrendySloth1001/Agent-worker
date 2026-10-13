-- OTA updates: sideloaded APK releases and the build each user last reported.

-- CreateTable
CREATE TABLE "app_releases" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "version" TEXT NOT NULL,
    "build" INTEGER NOT NULL,
    "kind" TEXT NOT NULL,
    "title" TEXT NOT NULL DEFAULT '',
    "notes" JSONB NOT NULL DEFAULT '[]',
    "apk_key" TEXT NOT NULL,
    "sha256" TEXT NOT NULL,
    "size" BIGINT NOT NULL,
    "min_supported_build" INTEGER,
    "status" TEXT NOT NULL DEFAULT 'draft',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "published_at" TIMESTAMPTZ(6),

    CONSTRAINT "app_releases_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "app_releases_kind_check" CHECK ("kind" IN ('patch', 'feature', 'major', 'critical')),
    CONSTRAINT "app_releases_status_check" CHECK ("status" IN ('draft', 'live', 'pulled'))
);

-- CreateTable
CREATE TABLE "app_installs" (
    "user_id" UUID NOT NULL,
    "build" INTEGER NOT NULL,
    "version" TEXT NOT NULL,
    "seen_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "app_installs_pkey" PRIMARY KEY ("user_id")
);

-- CreateIndex
CREATE UNIQUE INDEX "app_releases_build_key" ON "app_releases"("build");

-- AddForeignKey
ALTER TABLE "app_installs" ADD CONSTRAINT "app_installs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
