-- Chats started from the Android assistant overlay are saved with origin 'assistant'.
ALTER TABLE "conversations" DROP CONSTRAINT IF EXISTS "conversations_origin_check";
ALTER TABLE "conversations" ADD CONSTRAINT "conversations_origin_check"
  CHECK ("origin" IN ('fork', 'merge', 'assistant'));
