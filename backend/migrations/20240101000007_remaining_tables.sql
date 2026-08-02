-- Sync state tracking per device per file
CREATE TABLE IF NOT EXISTS sync_states (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    file_entry_id UUID NOT NULL REFERENCES file_entries(id) ON DELETE CASCADE,
    version BIGINT NOT NULL DEFAULT 1,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('synced', 'pending', 'conflict')),
    last_synced_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(device_id, file_entry_id)
);
CREATE INDEX idx_sync_states_user_device ON sync_states (user_id, device_id);
CREATE INDEX idx_sync_states_status ON sync_states (user_id, status) WHERE status != 'synced';

-- Sync folders configuration
CREATE TABLE IF NOT EXISTS sync_folders (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    local_path TEXT NOT NULL,
    remote_folder_id UUID REFERENCES file_entries(id) ON DELETE SET NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_sync_folders_user ON sync_folders (user_id);

-- Notifications
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    body TEXT NOT NULL DEFAULT '',
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_notifications_user ON notifications (user_id, is_read, created_at DESC);

-- Background jobs
CREATE TABLE IF NOT EXISTS jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    job_type VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'running', 'completed', 'failed')),
    details TEXT NOT NULL DEFAULT '',
    result TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);
CREATE INDEX idx_jobs_user ON jobs (user_id, status);

-- Backups
CREATE TABLE IF NOT EXISTS backups (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    size_bytes BIGINT NOT NULL DEFAULT 0,
    file_count BIGINT NOT NULL DEFAULT 0,
    storage_path TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);
CREATE INDEX idx_backups_user ON backups (user_id);

-- Backup schedules
CREATE TABLE IF NOT EXISTS backup_schedules (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    cron_expression VARCHAR(100) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    last_run_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_backup_schedules_user ON backup_schedules (user_id);

-- File tags (for AI tagging)
CREATE TABLE IF NOT EXISTS file_tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_entry_id UUID NOT NULL REFERENCES file_entries(id) ON DELETE CASCADE,
    tag VARCHAR(100) NOT NULL,
    source VARCHAR(20) NOT NULL DEFAULT 'ai' CHECK (source IN ('ai', 'user')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(file_entry_id, tag)
);
CREATE INDEX idx_file_tags_entry ON file_tags (file_entry_id);
CREATE INDEX idx_file_tags_tag ON file_tags (tag);
