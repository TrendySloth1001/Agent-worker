-- OTA v2 phase 2: in-house crash and error reporting (owner-only). Additive: new tables only.

-- Client sessions: one row per app process. outcome: ok | crash | anr | killed | unknown.
CREATE TABLE "app_sessions" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "build" INTEGER NOT NULL,
    "patch_number" INTEGER,
    "started_at" TIMESTAMPTZ(6) NOT NULL,
    "ended_at" TIMESTAMPTZ(6),
    "outcome" TEXT NOT NULL DEFAULT 'unknown',

    CONSTRAINT "app_sessions_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "app_sessions_outcome_check" CHECK ("outcome" IN ('ok', 'crash', 'anr', 'killed', 'unknown'))
);

-- One row per distinct error (fingerprint). status: open | resolved | ignored.
CREATE TABLE "app_error_groups" (
    "fingerprint" TEXT NOT NULL,
    "first_build" INTEGER NOT NULL,
    "last_build" INTEGER NOT NULL,
    "count" BIGINT NOT NULL DEFAULT 0,
    "users" INTEGER NOT NULL DEFAULT 0,
    "first_seen" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_seen" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "status" TEXT NOT NULL DEFAULT 'open',
    "title" TEXT NOT NULL DEFAULT '',
    "kind" TEXT NOT NULL DEFAULT 'dart',

    CONSTRAINT "app_error_groups_pkey" PRIMARY KEY ("fingerprint"),
    CONSTRAINT "app_error_groups_status_check" CHECK ("status" IN ('open', 'resolved', 'ignored'))
);

-- Per group and build: occurrence count and distinct users (kept after the sample events expire).
CREATE TABLE "app_error_group_builds" (
    "fingerprint" TEXT NOT NULL,
    "build" INTEGER NOT NULL,
    "count" BIGINT NOT NULL DEFAULT 0,
    "users" INTEGER NOT NULL DEFAULT 0,
    "first_seen" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_seen" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "app_error_group_builds_pkey" PRIMARY KEY ("fingerprint", "build")
);

-- Which users hit which group on which build (exact distinct-user math). Swept after 90 days.
CREATE TABLE "app_error_group_users" (
    "fingerprint" TEXT NOT NULL,
    "build" INTEGER NOT NULL,
    "user_id" UUID NOT NULL,
    "last_seen" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "app_error_group_users_pkey" PRIMARY KEY ("fingerprint", "build", "user_id")
);

-- Sample events (at most 5 per group per build). kind: dart | platform | isolate | kotlin | anr | native_signal.
CREATE TABLE "app_error_events" (
    "id" BIGSERIAL NOT NULL,
    "fingerprint" TEXT NOT NULL,
    "user_id" UUID NOT NULL,
    "build" INTEGER NOT NULL,
    "at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "kind" TEXT NOT NULL,
    "message" TEXT NOT NULL DEFAULT '',
    "stack" TEXT NOT NULL DEFAULT '',
    "breadcrumbs" JSONB NOT NULL DEFAULT '[]',
    "device" JSONB NOT NULL DEFAULT '{}',
    "session_id" UUID,

    CONSTRAINT "app_error_events_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "app_sessions_build_started_at_idx" ON "app_sessions"("build", "started_at");
CREATE INDEX "app_sessions_user_id_idx" ON "app_sessions"("user_id");
CREATE INDEX "app_error_groups_last_seen_idx" ON "app_error_groups"("last_seen");
CREATE INDEX "app_error_group_builds_build_idx" ON "app_error_group_builds"("build");
CREATE INDEX "app_error_events_fingerprint_at_idx" ON "app_error_events"("fingerprint", "at");
CREATE INDEX "app_error_events_user_at_idx" ON "app_error_events"("user_id", "at");

ALTER TABLE "app_sessions" ADD CONSTRAINT "app_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
ALTER TABLE "app_error_group_builds" ADD CONSTRAINT "app_error_group_builds_fingerprint_fkey" FOREIGN KEY ("fingerprint") REFERENCES "app_error_groups"("fingerprint") ON DELETE CASCADE ON UPDATE NO ACTION;
ALTER TABLE "app_error_group_users" ADD CONSTRAINT "app_error_group_users_fingerprint_fkey" FOREIGN KEY ("fingerprint") REFERENCES "app_error_groups"("fingerprint") ON DELETE CASCADE ON UPDATE NO ACTION;
ALTER TABLE "app_error_group_users" ADD CONSTRAINT "app_error_group_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
ALTER TABLE "app_error_events" ADD CONSTRAINT "app_error_events_fingerprint_fkey" FOREIGN KEY ("fingerprint") REFERENCES "app_error_groups"("fingerprint") ON DELETE CASCADE ON UPDATE NO ACTION;
ALTER TABLE "app_error_events" ADD CONSTRAINT "app_error_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
