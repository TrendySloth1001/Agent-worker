ALTER TABLE conversation_messages ADD COLUMN evidence jsonb NOT NULL DEFAULT '[]';
