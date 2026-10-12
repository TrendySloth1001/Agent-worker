-- The recorder also writes "github" calls and per-turn "turn" summaries; the old check rejected them (and dropped the whole batch).
ALTER TABLE "usage_events" DROP CONSTRAINT IF EXISTS "usage_events_kind_check";
ALTER TABLE "usage_events" ADD CONSTRAINT "usage_events_kind_check" CHECK (kind IN ('chat','embed','search','fetch','transcribe','github','turn'));
