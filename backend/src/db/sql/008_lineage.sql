-- Conversation lineage: forks copy a prefix of a chat, merges start from an AI briefing of two chats.
ALTER TABLE conversations ADD COLUMN origin text CHECK (origin IN ('fork','merge'));
ALTER TABLE conversations ADD COLUMN forked_from uuid REFERENCES conversations(id) ON DELETE SET NULL;
ALTER TABLE conversations ADD COLUMN fork_point int;
ALTER TABLE conversations ADD COLUMN merged_from uuid[] NOT NULL DEFAULT '{}';
CREATE INDEX conversations_forked_from_idx ON conversations (forked_from);

ALTER TABLE conversations DROP CONSTRAINT IF EXISTS conversations_title_source_check;
ALTER TABLE conversations ADD CONSTRAINT conversations_title_source_check CHECK (title_source IN ('ai','fallback','user','derived'));

ALTER TABLE conversation_messages DROP CONSTRAINT IF EXISTS conversation_messages_role_check;
ALTER TABLE conversation_messages ADD CONSTRAINT conversation_messages_role_check CHECK (role IN ('user','assistant','context'));
ALTER TABLE conversation_messages ADD COLUMN meta jsonb NOT NULL DEFAULT '{}';
