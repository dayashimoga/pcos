-- Share links for file/folder sharing
CREATE TABLE IF NOT EXISTS share_links (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    file_entry_id UUID NOT NULL REFERENCES file_entries(id) ON DELETE CASCADE,
    token VARCHAR(64) NOT NULL UNIQUE,
    permission VARCHAR(20) NOT NULL DEFAULT 'view' CHECK (permission IN ('view', 'download')),
    password_hash TEXT,
    expires_at TIMESTAMPTZ,
    max_downloads INTEGER,
    download_count INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_share_links_token ON share_links (token) WHERE is_active = true;
CREATE INDEX idx_share_links_user ON share_links (user_id);
