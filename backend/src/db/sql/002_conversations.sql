CREATE TABLE conversations (
  id uuid PRIMARY KEY,
  title text,
  title_source text CHECK (title_source IN ('ai','fallback','user')),
  message_count int NOT NULL DEFAULT 0,
  preview text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX conversations_updated_idx ON conversations (updated_at DESC);

CREATE TABLE conversation_messages (
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  position int NOT NULL,
  role text NOT NULL CHECK (role IN ('user','assistant')),
  content text NOT NULL,
  model text,
  citations jsonb NOT NULL DEFAULT '[]',
  used_ids text[] NOT NULL DEFAULT '{}',
  is_error boolean NOT NULL DEFAULT false,
  PRIMARY KEY (conversation_id, position)
);
