-- Accounts, refresh-token sessions and per-user daily usage.
-- Existing rows keep user_id NULL until the owner account registers; that
-- registration claims them in the same transaction (see auth/service.ts).
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email citext NOT NULL UNIQUE,
  password_hash text NOT NULL,
  name text NOT NULL DEFAULT '',
  avatar_url text,
  role text NOT NULL DEFAULT 'user' CHECK (role IN ('owner','user')),
  -- Per-user overrides of the configured daily limits, e.g. {"chat": 5}.
  limits jsonb NOT NULL DEFAULT '{}',
  disabled boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_login_at timestamptz
);
-- At most one owner.
CREATE UNIQUE INDEX users_one_owner ON users ((role)) WHERE role = 'owner';

-- One row per refresh token. A login starts a family (= a device session);
-- each refresh revokes the presented token and adds its successor.
CREATE TABLE auth_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id uuid NOT NULL,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  device text,
  created_at timestamptz NOT NULL DEFAULT now(),
  family_created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  replaced_by uuid
);
CREATE INDEX auth_sessions_user_idx ON auth_sessions (user_id);
CREATE INDEX auth_sessions_family_idx ON auth_sessions (family_id);

CREATE TABLE user_daily_usage (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day date NOT NULL,
  chats int NOT NULL DEFAULT 0,
  tables int NOT NULL DEFAULT 0,
  uploads int NOT NULL DEFAULT 0,
  bytes bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, day)
);

-- Ownership. Child tables (messages, documents, chunks, file_chunks) follow
-- their parent through ON DELETE CASCADE.
ALTER TABLE conversations ADD COLUMN user_id uuid REFERENCES users(id) ON DELETE CASCADE;
CREATE INDEX conversations_user_idx ON conversations (user_id, updated_at DESC);

ALTER TABLE files ADD COLUMN user_id uuid REFERENCES users(id) ON DELETE CASCADE;
CREATE INDEX files_user_idx ON files (user_id);

ALTER TABLE sources ADD COLUMN user_id uuid REFERENCES users(id) ON DELETE CASCADE;
CREATE INDEX sources_user_idx ON sources (user_id);
-- The same URL may be ingested by different users.
ALTER TABLE sources DROP CONSTRAINT IF EXISTS sources_type_uri_key;
ALTER TABLE sources ADD CONSTRAINT sources_user_type_uri_key UNIQUE NULLS NOT DISTINCT (user_id, type, uri);
