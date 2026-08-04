//! Video/audio adaptive streaming service.
//!
//! Manages media transcoding via Docker-based FFmpeg, serves HLS streams,
//! and provides media metadata probing.
//!
//! Architecture: Backend dispatches transcoding jobs to the `pcos-transcoder` Docker
//! container. Transcoded HLS segments are stored alongside the original file.

use pcos_common::error::{AppError, AppResult};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

/// Transcoding job status.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::Type, PartialEq)]
#[sqlx(type_name = "VARCHAR", rename_all = "snake_case")]
pub enum TranscodeStatus {
    Pending,
    Processing,
    Completed,
    Failed,
}

/// Transcoding profile — determines output quality levels.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TranscodeProfile {
    Adaptive,  // 360p + 720p + 1080p HLS
    AudioOnly, // HLS audio + MP3 fallback
    Thumbnail, // Preview thumbnail + sprite sheet
}

impl TranscodeProfile {
    pub fn as_str(&self) -> &str {
        match self {
            TranscodeProfile::Adaptive => "adaptive",
            TranscodeProfile::AudioOnly => "audio-only",
            TranscodeProfile::Thumbnail => "thumbnail",
        }
    }
}

/// Media metadata from ffprobe.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MediaInfo {
    pub duration_secs: f64,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub video_codec: Option<String>,
    pub audio_codec: Option<String>,
    pub bitrate_kbps: Option<u64>,
    pub format: String,
    pub has_video: bool,
    pub has_audio: bool,
}

/// Transcoding job record.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct TranscodeJob {
    pub id: Uuid,
    pub file_id: Uuid,
    pub user_id: Uuid,
    pub profile: String,
    pub status: String,
    pub input_path: String,
    pub output_dir: String,
    pub master_playlist: Option<String>,
    pub error_message: Option<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub completed_at: Option<chrono::DateTime<chrono::Utc>>,
}

/// Queue a transcoding job.
pub async fn queue_transcode(
    pool: &PgPool,
    file_id: Uuid,
    user_id: Uuid,
    input_path: &str,
    profile: TranscodeProfile,
) -> AppResult<TranscodeJob> {
    let id = Uuid::new_v4();
    let output_dir = format!("{}_hls", input_path.trim_end_matches(|c: char| c != '.'));

    let job = sqlx::query_as::<_, TranscodeJob>(
        "INSERT INTO transcode_jobs (id, file_id, user_id, profile, status, input_path, output_dir, created_at) \
         VALUES ($1, $2, $3, $4, 'pending', $5, $6, NOW()) RETURNING *"
    )
    .bind(id).bind(file_id).bind(user_id)
    .bind(profile.as_str()).bind(input_path).bind(&output_dir)
    .fetch_one(pool).await?;

    tracing::info!(job_id = %id, file_id = %file_id, profile = %profile.as_str(), "Transcode job queued");
    Ok(job)
}

/// Execute a transcoding job by running the FFmpeg Docker container.
/// This should be called from a background worker.
pub async fn execute_transcode(pool: &PgPool, job_id: Uuid) -> AppResult<TranscodeJob> {
    // Mark as processing
    sqlx::query("UPDATE transcode_jobs SET status = 'processing' WHERE id = $1")
        .bind(job_id)
        .execute(pool)
        .await?;

    let job: TranscodeJob = sqlx::query_as("SELECT * FROM transcode_jobs WHERE id = $1")
        .bind(job_id)
        .fetch_one(pool)
        .await?;

    // Run FFmpeg via Docker
    let output = tokio::process::Command::new("docker")
        .args([
            "run",
            "--rm",
            "-v",
            &format!(
                "{}:{}",
                std::env::var("PCOS_STORAGE__BASE_PATH").unwrap_or("/data/pcos/storage".into()),
                "/data"
            ),
            "pcos-transcoder:latest",
            "transcode",
            &job.input_path,
            &job.output_dir,
            &job.profile,
        ])
        .output()
        .await
        .map_err(|e| AppError::Internal(format!("Docker transcode failed: {e}")))?;

    if output.status.success() {
        let master = format!(
            "{}/{}.m3u8",
            job.output_dir,
            std::path::Path::new(&job.input_path)
                .file_stem()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or("stream".into())
        );

        sqlx::query(
            "UPDATE transcode_jobs SET status = 'completed', master_playlist = $1, completed_at = NOW() WHERE id = $2"
        ).bind(&master).bind(job_id).execute(pool).await?;

        tracing::info!(job_id = %job_id, "Transcode completed: {}", master);
    } else {
        let err = String::from_utf8_lossy(&output.stderr).to_string();
        sqlx::query(
            "UPDATE transcode_jobs SET status = 'failed', error_message = $1, completed_at = NOW() WHERE id = $2"
        ).bind(&err).bind(job_id).execute(pool).await?;

        tracing::error!(job_id = %job_id, "Transcode failed: {}", err);
    }

    sqlx::query_as("SELECT * FROM transcode_jobs WHERE id = $1")
        .bind(job_id)
        .fetch_one(pool)
        .await
        .map_err(|e| AppError::Internal(e.to_string()))
}

/// Probe media file metadata via Docker ffprobe.
pub async fn probe_media(file_path: &str) -> AppResult<MediaInfo> {
    let output = tokio::process::Command::new("docker")
        .args([
            "run",
            "--rm",
            "-v",
            &format!(
                "{}:{}",
                std::env::var("PCOS_STORAGE__BASE_PATH").unwrap_or("/data/pcos/storage".into()),
                "/data"
            ),
            "pcos-transcoder:latest",
            "probe",
            file_path,
        ])
        .output()
        .await
        .map_err(|e| AppError::Internal(format!("ffprobe failed: {e}")))?;

    let json_str = String::from_utf8_lossy(&output.stdout);
    let probe: serde_json::Value = serde_json::from_str(&json_str)
        .map_err(|e| AppError::Internal(format!("ffprobe parse error: {e}")))?;

    let format = &probe["format"];
    let streams = probe["streams"].as_array();

    let mut info = MediaInfo {
        duration_secs: format["duration"]
            .as_str()
            .and_then(|s| s.parse().ok())
            .unwrap_or(0.0),
        width: None,
        height: None,
        video_codec: None,
        audio_codec: None,
        bitrate_kbps: format["bit_rate"]
            .as_str()
            .and_then(|s| s.parse::<u64>().ok())
            .map(|b| b / 1000),
        format: format["format_name"]
            .as_str()
            .unwrap_or("unknown")
            .to_string(),
        has_video: false,
        has_audio: false,
    };

    if let Some(streams) = streams {
        for stream in streams {
            match stream["codec_type"].as_str() {
                Some("video") => {
                    info.has_video = true;
                    info.width = stream["width"].as_u64().map(|w| w as u32);
                    info.height = stream["height"].as_u64().map(|h| h as u32);
                    info.video_codec = stream["codec_name"].as_str().map(String::from);
                }
                Some("audio") => {
                    info.has_audio = true;
                    info.audio_codec = stream["codec_name"].as_str().map(String::from);
                }
                _ => {}
            }
        }
    }

    Ok(info)
}

/// List transcoding jobs for a user.
pub async fn list_jobs(pool: &PgPool, user_id: Uuid) -> AppResult<Vec<TranscodeJob>> {
    Ok(sqlx::query_as::<_, TranscodeJob>(
        "SELECT * FROM transcode_jobs WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?)
}

/// Get the HLS stream URL for a completed transcoding job.
pub async fn get_stream_url(pool: &PgPool, job_id: Uuid, user_id: Uuid) -> AppResult<String> {
    let job: TranscodeJob =
        sqlx::query_as("SELECT * FROM transcode_jobs WHERE id = $1 AND user_id = $2")
            .bind(job_id)
            .bind(user_id)
            .fetch_one(pool)
            .await
            .map_err(|_| AppError::NotFound("Transcode job not found".into()))?;

    job.master_playlist
        .ok_or_else(|| AppError::Validation("Transcoding not yet completed".into()))
}
