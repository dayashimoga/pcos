-- Registered devices
CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    device_type VARCHAR(50) NOT NULL,
    os VARCHAR(50) NOT NULL,
    os_version VARCHAR(50) NOT NULL DEFAULT '',
    agent_version VARCHAR(50) NOT NULL DEFAULT '',
    is_online BOOLEAN NOT NULL DEFAULT false,
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_devices_user_id ON devices (user_id);
CREATE INDEX idx_devices_is_online ON devices (is_online) WHERE is_online = true;
