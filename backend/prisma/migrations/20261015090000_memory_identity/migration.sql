-- An "identity" kind (name, nickname, location, job) for memories.
ALTER TABLE "memories" DROP CONSTRAINT IF EXISTS "memories_kind_check";
ALTER TABLE "memories" ADD CONSTRAINT "memories_kind_check"
  CHECK ("kind" IN ('identity','fact','preference','project','instruction'));

-- Notes about memory itself ("User wants to be remembered.") were never facts.
DELETE FROM "memories"
WHERE "text" ~* '^(the\s+)?user\s+(wants|would like|asked|asks)\s+(to\s+be\s+|you\s+to\s+|sparky\s+to\s+)?remember';

-- Contact-card wording: "User is named Nick." -> "Name is Nick.",
-- "User prefers tea." -> "Prefers tea.".
UPDATE "memories"
SET "text" = regexp_replace("text", '^(the\s+)?user(''s)?\s+is\s+named\s+', 'Name is ', 'i')
WHERE "text" ~* '^(the\s+)?user(''s)?\s+is\s+named\s+';

UPDATE "memories"
SET "text" = upper(substr(regexp_replace("text", '^(the\s+)?user(''s)?\s+', '', 'i'), 1, 1))
          || substr(regexp_replace("text", '^(the\s+)?user(''s)?\s+', '', 'i'), 2)
WHERE "text" ~* '^(the\s+)?user(''s)?\s+';

-- Name memories become identity.
UPDATE "memories" SET "kind" = 'identity'
WHERE "kind" = 'fact' AND "text" ~* '^(name is|goes by|lives in|pronouns)';
