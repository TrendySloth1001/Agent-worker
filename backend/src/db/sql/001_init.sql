CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE sources (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL CHECK (type IN ('web','github','stackoverflow','reddit','hackernews')),
  uri text NOT NULL,
  title text,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','running','ready','failed')),
  options jsonb NOT NULL DEFAULT '{}',
  error text,
  progress_done int NOT NULL DEFAULT 0,
  progress_total int,
  doc_count int NOT NULL DEFAULT 0,
  chunk_count int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  last_ingested_at timestamptz,
  UNIQUE (type, uri)
);

CREATE TABLE documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id uuid NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  url text NOT NULL,
  title text,
  content_hash text,
  meta jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_id, url)
);

CREATE TABLE chunks (
  id bigserial PRIMARY KEY,
  document_id uuid NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  source_id uuid NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  ord int NOT NULL,
  heading_path text,
  content text NOT NULL,
  token_count int,
  content_hash text NOT NULL,
  embedding vector(1024) NOT NULL,
  tsv tsvector GENERATED ALWAYS AS (to_tsvector('english', content)) STORED,
  UNIQUE (document_id, ord)
);
CREATE INDEX chunks_embedding_hnsw ON chunks USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
CREATE INDEX chunks_tsv_gin ON chunks USING gin (tsv);
CREATE INDEX chunks_source_idx ON chunks (source_id);
CREATE INDEX documents_source_idx ON documents (source_id);

CREATE TABLE kb_meta (key text PRIMARY KEY, value text NOT NULL);

CREATE TABLE usage_events (
  id bigserial PRIMARY KEY,
  ts timestamptz NOT NULL DEFAULT now(),
  provider text NOT NULL,
  model text,
  kind text NOT NULL CHECK (kind IN ('chat','embed','search','fetch')),
  ok boolean NOT NULL,
  status int,
  latency_ms int,
  count int NOT NULL DEFAULT 1,
  prompt_tokens int,
  completion_tokens int
);
CREATE INDEX usage_events_ts_idx ON usage_events (ts);
CREATE INDEX usage_events_provider_ts_idx ON usage_events (provider, ts);
