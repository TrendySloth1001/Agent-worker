-- Encryption of user data at rest (src/crypto/userData.ts). Additive; existing rows stay readable
-- (plaintext is accepted on read) until `pnpm data:encrypt` seals them.

-- Each user's data key, wrapped with the server's DATA_KEY.
ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "data_key_enc" TEXT;

-- Memory slots: "slot" becomes a keyed blind index (equality + uniqueness still work), the real name is sealed here.
ALTER TABLE "memories" ADD COLUMN IF NOT EXISTS "slot_enc" TEXT;

-- chunks.tsv was GENERATED from content; content is now ciphertext, so the app writes tsv itself.
-- DROP EXPRESSION keeps the existing values and the GIN index; new rows get strip(to_tsvector(...)) from the app.
ALTER TABLE "chunks" ALTER COLUMN "tsv" DROP EXPRESSION IF EXISTS;

-- Indexes over plaintext content: useless on ciphertext and they would keep lexemes of the old text.
-- Search over chats and memory is now done in the app on decrypted text, scoped to the user.
DROP INDEX IF EXISTS "conversations_title_trgm";
DROP INDEX IF EXISTS "conversation_messages_content_trgm";
DROP INDEX IF EXISTS "conversation_messages_content_fts";
DROP INDEX IF EXISTS "chunks_content_trgm";
