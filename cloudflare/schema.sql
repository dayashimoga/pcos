-- PCOS Edge Control Plane D1 Database Schema
-- Provides authoritative metadata, device registry, storage topology, and pairing.

CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    display_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'user',
    quota_bytes INTEGER NOT NULL DEFAULT 53687091200, -- 50GB default
    used_bytes INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS cloud_identities (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    cloud_id TEXT UNIQUE NOT NULL,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS device_identities (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    cloud_id TEXT NOT NULL,
    name TEXT NOT NULL,
    device_type TEXT NOT NULL, -- 'desktop', 'laptop', 'phone', 'tablet', 'nas', 'tv', 'web'
    os TEXT NOT NULL,
    os_version TEXT NOT NULL DEFAULT '',
    agent_version TEXT NOT NULL DEFAULT '',
    public_key TEXT,
    is_online INTEGER NOT NULL DEFAULT 0,
    last_seen_at TEXT,
    last_lan_ip TEXT,
    wireguard_pubkey TEXT,
    relay_endpoint TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_devices_user ON device_identities(user_id);
CREATE INDEX IF NOT EXISTS idx_devices_online ON device_identities(user_id, is_online);

CREATE TABLE IF NOT EXISTS storage_nodes (
    id TEXT PRIMARY KEY,
    device_id TEXT NOT NULL REFERENCES device_identities(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    storage_path TEXT NOT NULL,
    total_capacity_bytes INTEGER NOT NULL DEFAULT 0,
    available_capacity_bytes INTEGER NOT NULL DEFAULT 0,
    is_online INTEGER NOT NULL DEFAULT 0,
    capabilities_json TEXT NOT NULL DEFAULT '{"ffmpeg":false,"ocr":false,"tantivy":false,"ollama":false}',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_storage_nodes_user ON storage_nodes(user_id);

CREATE TABLE IF NOT EXISTS file_locations (
    file_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    storage_node_id TEXT NOT NULL REFERENCES storage_nodes(id) ON DELETE CASCADE,
    relative_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    mime_type TEXT NOT NULL,
    sha256_checksum TEXT NOT NULL,
    replication_policy TEXT NOT NULL DEFAULT 'device_only', -- 'device_only', 'any_device', 'always_available_remote', 'redundant_copy', 'archive'
    r2_cached_key TEXT,
    r2_cached_size INTEGER DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_files_user ON file_locations(user_id);
CREATE INDEX IF NOT EXISTS idx_files_node ON file_locations(storage_node_id);

CREATE TABLE IF NOT EXISTS pairing_sessions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pairing_code TEXT UNIQUE NOT NULL,
    enrollment_token TEXT UNIQUE NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending_redeem', -- 'pending_redeem', 'pending_approval', 'approved', 'rejected', 'expired'
    failed_attempts INTEGER NOT NULL DEFAULT 0,
    candidate_device_json TEXT,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_pairing_code ON pairing_sessions(pairing_code);
CREATE INDEX IF NOT EXISTS idx_pairing_token ON pairing_sessions(enrollment_token);

CREATE TABLE IF NOT EXISTS refresh_tokens (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    revoked INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_tokens_hash ON refresh_tokens(token_hash);

CREATE TABLE IF NOT EXISTS shares (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    file_id TEXT NOT NULL,
    share_token TEXT UNIQUE NOT NULL,
    is_public INTEGER NOT NULL DEFAULT 1,
    is_upload_request INTEGER NOT NULL DEFAULT 0,
    password_hash TEXT,
    expires_at TEXT,
    max_downloads INTEGER,
    download_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_shares_token ON shares(share_token);

CREATE TABLE IF NOT EXISTS audit_logs (
    id TEXT PRIMARY KEY,
    user_id TEXT,
    device_id TEXT,
    action TEXT NOT NULL,
    details_json TEXT,
    ip_address TEXT,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS free_tier_usage (
    date_key TEXT PRIMARY KEY, -- 'YYYY-MM-DD'
    worker_requests INTEGER NOT NULL DEFAULT 0,
    d1_reads INTEGER NOT NULL DEFAULT 0,
    d1_writes INTEGER NOT NULL DEFAULT 0,
    do_requests INTEGER NOT NULL DEFAULT 0,
    r2_storage_bytes INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL
);
