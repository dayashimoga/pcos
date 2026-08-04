-- File versioning table
CREATE TABLE IF NOT EXISTS file_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_entry_id UUID NOT NULL REFERENCES file_entries(id) ON DELETE CASCADE,
    version_number INTEGER NOT NULL DEFAULT 1,
    size_bytes BIGINT NOT NULL DEFAULT 0,
    sha256_hash VARCHAR(64),
    storage_path TEXT NOT NULL,
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(file_entry_id, version_number)
);

CREATE INDEX idx_file_versions_file ON file_versions(file_entry_id);

-- User roles for RBAC
ALTER TABLE users ADD COLUMN IF NOT EXISTS role VARCHAR(20) NOT NULL DEFAULT 'user';
-- Roles: 'admin', 'user', 'viewer'

-- TOTP/MFA support
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_secret TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_enabled BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_verified_at TIMESTAMPTZ;

-- Storage quotas
ALTER TABLE users ADD COLUMN IF NOT EXISTS storage_quota_bytes BIGINT NOT NULL DEFAULT 10737418240; -- 10 GB default
