-- Migration 00012: Family Clouds, Recovery Keys, Storage Policies, Replicas & Cluster Protection
-- Part of PCOS Production-Grade Hardening (Phases 1, 2, 4)

-- 1. Family Clouds & Multi-Tenant Isolation
CREATE TABLE IF NOT EXISTS family_clouds (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    cloud_type VARCHAR(32) NOT NULL DEFAULT 'family', -- 'personal', 'family', 'self_hosted'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_family_owner ON family_clouds(owner_id);

CREATE TABLE IF NOT EXISTS family_members (
    id VARCHAR(64) PRIMARY KEY,
    cloud_id VARCHAR(64) NOT NULL REFERENCES family_clouds(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(32) NOT NULL DEFAULT 'member', -- 'owner', 'admin', 'member', 'child'
    storage_quota_bytes BIGINT NOT NULL DEFAULT 21474836480, -- 20GB default
    used_bytes BIGINT NOT NULL DEFAULT 0,
    invite_code VARCHAR(64),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(cloud_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_family_members_cloud ON family_members(cloud_id);
CREATE INDEX IF NOT EXISTS idx_family_members_user ON family_members(user_id);

-- 2. Emergency Account Recovery
CREATE TABLE IF NOT EXISTS recovery_keys (
    id VARCHAR(64) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recovery_hash VARCHAR(128) NOT NULL,
    hint VARCHAR(255),
    is_used BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_recovery_user ON recovery_keys(user_id);

-- 3. Storage Policies & Placement Engine
CREATE TABLE IF NOT EXISTS storage_policies (
    id VARCHAR(64) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category VARCHAR(64) NOT NULL, -- 'photos', 'videos', 'audio', 'documents', 'backups', 'important', 'custom'
    mime_patterns TEXT NOT NULL,
    target_storage_type VARCHAR(32) NOT NULL DEFAULT 'any', -- 'ssd', 'hdd', 'usb', 'nas', 'any'
    target_node_id VARCHAR(64),
    replica_count INT NOT NULL DEFAULT 1,
    availability_tier VARCHAR(32) NOT NULL DEFAULT 'local_only',
    priority INT NOT NULL DEFAULT 10,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_storage_policies_user ON storage_policies(user_id);

-- 4. File Replicas & Cluster Protection
CREATE TABLE IF NOT EXISTS file_replicas (
    id VARCHAR(64) PRIMARY KEY,
    file_id UUID NOT NULL REFERENCES file_entries(id) ON DELETE CASCADE,
    storage_node_id VARCHAR(64) NOT NULL,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    status VARCHAR(32) NOT NULL DEFAULT 'synced', -- 'pending_sync', 'synced', 'stale', 'failed'
    checksum VARCHAR(128) NOT NULL,
    verified_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(file_id, storage_node_id)
);

CREATE INDEX IF NOT EXISTS idx_file_replicas_file ON file_replicas(file_id);

CREATE TABLE IF NOT EXISTS cluster_protection (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    protection_mode VARCHAR(32) NOT NULL DEFAULT 'single_device', -- 'single_device', 'two_node_protection', 'always_on_nas', 'multi_node_mesh'
    rpo_target_minutes INT NOT NULL DEFAULT 60,
    rto_target_minutes INT NOT NULL DEFAULT 15,
    auto_rebalance BOOLEAN NOT NULL DEFAULT true,
    last_health_check TIMESTAMPTZ,
    health_status VARCHAR(32) NOT NULL DEFAULT 'healthy',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
