-- Shared web-search cache: provider results by (provider, freshness class, normalised query), reused across users, restarts and round-table seats.

-- CreateTable
CREATE TABLE "web_cache" (
    "key" TEXT NOT NULL,
    "payload" JSONB NOT NULL,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "web_cache_pkey" PRIMARY KEY ("key")
);

-- CreateIndex
CREATE INDEX "web_cache_expires_at_idx" ON "web_cache"("expires_at");
