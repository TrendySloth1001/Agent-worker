ALTER TABLE conversations ADD COLUMN pinned_at timestamptz;
ALTER TABLE conversations ADD COLUMN archived_at timestamptz;
CREATE INDEX conversations_list_idx ON conversations ((archived_at IS NULL), (pinned_at IS NOT NULL) DESC, updated_at DESC);
