-- File entries (files and folders in a unified table)
CREATE TABLE IF NOT EXISTS file_entries (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES file_entries(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    entry_type VARCHAR(10) NOT NULL CHECK (entry_type IN ('file', 'folder')),
    mime_type VARCHAR(255),
    size_bytes BIGINT NOT NULL DEFAULT 0,
    sha256_hash VARCHAR(64),
    storage_path TEXT,
    is_trashed BOOLEAN NOT NULL DEFAULT false,
    trashed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Prevent duplicate names within the same parent for the same user
    CONSTRAINT uq_file_entries_parent_name UNIQUE NULLS NOT DISTINCT (user_id, parent_id, name, is_trashed)
);

CREATE INDEX idx_file_entries_user_id ON file_entries (user_id);
CREATE INDEX idx_file_entries_parent_id ON file_entries (user_id, parent_id) WHERE is_trashed = false;
CREATE INDEX idx_file_entries_trashed ON file_entries (user_id, is_trashed) WHERE is_trashed = true;
CREATE INDEX idx_file_entries_hash ON file_entries (sha256_hash) WHERE sha256_hash IS NOT NULL;
CREATE INDEX idx_file_entries_type ON file_entries (user_id, entry_type) WHERE is_trashed = false;
