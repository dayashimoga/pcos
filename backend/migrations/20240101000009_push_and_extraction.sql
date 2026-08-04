-- Push notification subscriptions (Web Push API)
CREATE TABLE IF NOT EXISTS push_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    endpoint TEXT NOT NULL UNIQUE,
    p256dh_key TEXT NOT NULL,
    auth_key TEXT NOT NULL,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_push_subs_user ON push_subscriptions(user_id);
CREATE INDEX idx_push_subs_endpoint ON push_subscriptions(endpoint);

-- Text extraction cache (OCR results)
CREATE TABLE IF NOT EXISTS text_extractions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id UUID NOT NULL REFERENCES file_entries(id) ON DELETE CASCADE,
    extracted_text TEXT NOT NULL DEFAULT '',
    method VARCHAR(50) NOT NULL DEFAULT 'unknown',
    confidence REAL NOT NULL DEFAULT 0.0,
    page_count INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_text_extract_file ON text_extractions(file_id);
CREATE INDEX idx_text_extract_fulltext ON text_extractions USING gin(to_tsvector('english', extracted_text));
