-- Slot-based memories (src/memory/slots.ts): one memory per slot per user
-- ("name", "location", "hometown", "work", "role", "pronouns", "birthday",
-- "languages", "tool:<tech>", "taste:<thing>"). Free-form notes keep NULL.
ALTER TABLE "memories" ADD COLUMN IF NOT EXISTS "slot" TEXT;

-- Backfill the identity slots from the contact-card wording. When a user has
-- several notes for one slot, only the most recently updated one gets it (the
-- others stay free-form, so nothing is lost and the unique index holds). A
-- full-name note beats a nickname-only one.
WITH guessed AS (
  SELECT "id", "user_id", "updated_at", "text",
    CASE
      WHEN "text" ~* '^(name is|goes by|prefers to be called)\M' THEN 'name'
      WHEN "text" ~* '^lives in\M' THEN 'location'
      WHEN "text" ~* '^(from|born in|originally from)\M' THEN 'hometown'
      WHEN "text" ~* '^(works at|works for|studies at|self-employed)' THEN 'work'
      WHEN "text" ~* '^works as\M' THEN 'role'
      WHEN "text" ~* '^pronouns\M' THEN 'pronouns'
      WHEN "text" ~* '^(birthday|born on)\M' THEN 'birthday'
      WHEN "text" ~* '^speaks\M' THEN 'languages'
    END AS "slot"
  FROM "memories"
  WHERE "slot" IS NULL AND "kind" NOT IN ('project', 'instruction')
),
ranked AS (
  SELECT "id", "slot", row_number() OVER (PARTITION BY "user_id", "slot" ORDER BY ("text" ~* '^name is') DESC, "updated_at" DESC) AS rn
  FROM guessed
  WHERE "slot" IS NOT NULL
)
UPDATE "memories" m
SET "slot" = r."slot"
FROM ranked r
WHERE m."id" = r."id" AND r.rn = 1
  AND NOT EXISTS (SELECT 1 FROM "memories" x WHERE x."user_id" = m."user_id" AND x."slot" = r."slot");

-- Slot notes are about who the user is.
UPDATE "memories" SET "kind" = 'identity'
WHERE "slot" IN ('name', 'location', 'hometown', 'work', 'role', 'pronouns', 'birthday', 'languages') AND "kind" = 'fact';

CREATE UNIQUE INDEX IF NOT EXISTS "memories_user_slot" ON "memories" ("user_id", "slot") WHERE "slot" IS NOT NULL;
