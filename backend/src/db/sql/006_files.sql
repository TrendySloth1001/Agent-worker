CREATE TABLE files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid,
  name text NOT NULL,
  mime text NOT NULL,
  size bigint NOT NULL,
  kind text NOT NULL CHECK (kind IN ('image','document','video','audio')),
  status text NOT NULL DEFAULT 'processing' CHECK (status IN ('processing','ready','failed')),
  error text,
  s3_key text NOT NULL,
  thumb_key text,
  meta jsonb NOT NULL DEFAULT '{}',
  text text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX files_conversation_idx ON files (conversation_id);

CREATE TABLE file_chunks (
  id bigserial PRIMARY KEY,
  file_id uuid NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  ord int NOT NULL,
  content text NOT NULL,
  embedding vector(1024) NOT NULL,
  UNIQUE (file_id, ord)
);
CREATE INDEX file_chunks_embedding_hnsw ON file_chunks USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);

ALTER TABLE conversation_messages ADD COLUMN attachments jsonb NOT NULL DEFAULT '[]';

ALTER TABLE usage_events DROP CONSTRAINT IF EXISTS usage_events_kind_check;
ALTER TABLE usage_events ADD CONSTRAINT usage_events_kind_check CHECK (kind IN ('chat','embed','search','fetch','transcribe'));
