-- Update share_links check constraint to allow upload permission for recipient file requests
ALTER TABLE share_links DROP CONSTRAINT IF EXISTS share_links_permission_check;
ALTER TABLE share_links ADD CONSTRAINT share_links_permission_check CHECK (permission IN ('view', 'download', 'upload'));

-- Playback progress tracking for media resume
CREATE TABLE IF NOT EXISTS playback_progress (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    file_entry_id UUID NOT NULL REFERENCES file_entries(id) ON DELETE CASCADE,
    position_secs FLOAT NOT NULL DEFAULT 0,
    duration_secs FLOAT NOT NULL DEFAULT 0,
    completed BOOLEAN NOT NULL DEFAULT false,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, file_entry_id)
);
CREATE INDEX IF NOT EXISTS idx_playback_progress_user ON playback_progress(user_id, updated_at DESC);
