-- Transcoding jobs table
CREATE TABLE IF NOT EXISTS transcode_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id UUID NOT NULL REFERENCES file_entries(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    profile VARCHAR(50) NOT NULL DEFAULT 'adaptive',
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    input_path TEXT NOT NULL,
    output_dir TEXT NOT NULL,
    master_playlist TEXT,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

CREATE INDEX idx_transcode_jobs_user ON transcode_jobs(user_id);
CREATE INDEX idx_transcode_jobs_file ON transcode_jobs(file_id);
CREATE INDEX idx_transcode_jobs_status ON transcode_jobs(status);
