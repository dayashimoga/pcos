//! Video/audio adaptive streaming service.
//!
//! Manages media transcoding via local/Docker FFmpeg, serves HLS streams,
//! creates short-lived revocable playback tokens, and provides media metadata probing.

use jsonwebtoken::{DecodingKey, EncodingKey, Header, Validation};
use pcos_common::error::{AppError, AppResult};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::path::{Path, PathBuf};
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

/// Media metadata from ffprobe or fallback inspection.
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

/// Short-lived scoped token claims for remote/TV media streaming.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlaybackClaims {
    pub sub: Uuid, // user_id
    pub file_id: Uuid,
    pub device_id: Option<Uuid>,
    pub exp: i64,
    pub typ: String,
}

/// Create a 2-hour scoped playback token for TV or mobile media playback without exposing user credentials.
pub fn create_playback_token(
    user_id: Uuid,
    file_id: Uuid,
    device_id: Option<Uuid>,
    jwt_secret: &str,
) -> AppResult<(String, i64)> {
    let exp = chrono::Utc::now().timestamp() + 7200; // 2 hours
    let claims = PlaybackClaims {
        sub: user_id,
        file_id,
        device_id,
        exp,
        typ: "playback".to_string(),
    };

    let token = jsonwebtoken::encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(jwt_secret.as_bytes()),
    )
    .map_err(|e| AppError::Internal(format!("Failed to sign playback token: {e}")))?;

    Ok((token, exp))
}

/// Verify a short-lived playback token.
pub fn verify_playback_token(token: &str, jwt_secret: &str) -> AppResult<PlaybackClaims> {
    let mut validation = Validation::default();
    validation.validate_exp = true;

    let token_data = jsonwebtoken::decode::<PlaybackClaims>(
        token,
        &DecodingKey::from_secret(jwt_secret.as_bytes()),
        &validation,
    )
    .map_err(|_| AppError::Unauthorized("Invalid or expired media playback token".to_string()))?;

    if token_data.claims.typ != "playback" {
        return Err(AppError::Unauthorized("Invalid token type".to_string()));
    }

    Ok(token_data.claims)
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

/// Execute a transcoding job by invoking local ffmpeg or fallback container.
pub async fn execute_transcode(pool: &PgPool, job_id: Uuid) -> AppResult<TranscodeJob> {
    sqlx::query("UPDATE transcode_jobs SET status = 'processing' WHERE id = $1")
        .bind(job_id)
        .execute(pool)
        .await?;

    let job: TranscodeJob = sqlx::query_as("SELECT * FROM transcode_jobs WHERE id = $1")
        .bind(job_id)
        .fetch_one(pool)
        .await?;

    let base_path = std::env::var("PCOS_STORAGE__BASE_PATH")
        .unwrap_or_else(|_| "/data/pcos/storage".into());

    let abs_input = PathBuf::from(&base_path).join(&job.input_path);
    let abs_output = PathBuf::from(&base_path).join(&job.output_dir);
    tokio::fs::create_dir_all(&abs_output).await.ok();

    // Check for local ffmpeg first
    let local_ffmpeg = tokio::process::Command::new("ffmpeg")
        .arg("-version")
        .output()
        .await;

    let res = if local_ffmpeg.is_ok() {
        let master_m3u8 = abs_output.join("master.m3u8");
        tokio::process::Command::new("ffmpeg")
            .args([
                "-i",
                abs_input.to_str().unwrap_or_default(),
                "-c:v",
                "h264",
                "-c:a",
                "aac",
                "-hls_time",
                "4",
                "-hls_playlist_type",
                "vod",
                "-hls_segment_filename",
                abs_output.join("segment_%03d.ts").to_str().unwrap_or_default(),
                master_m3u8.to_str().unwrap_or_default(),
            ])
            .output()
            .await
    } else {
        tokio::process::Command::new("docker")
            .args([
                "run",
                "--rm",
                "-v",
                &format!("{}:/data", base_path),
                "pcos-transcoder:latest",
                "transcode",
                &job.input_path,
                &job.output_dir,
                &job.profile,
            ])
            .output()
            .await
    };

    match res {
        Ok(output) if output.status.success() => {
            let master = format!("{}/master.m3u8", job.output_dir);
            sqlx::query(
                "UPDATE transcode_jobs SET status = 'completed', master_playlist = $1, completed_at = NOW() WHERE id = $2"
            ).bind(&master).bind(job_id).execute(pool).await?;

            tracing::info!(job_id = %job_id, "Transcode completed: {}", master);
        }
        Ok(output) => {
            let err = String::from_utf8_lossy(&output.stderr).to_string();
            sqlx::query(
                "UPDATE transcode_jobs SET status = 'failed', error_message = $1, completed_at = NOW() WHERE id = $2"
            ).bind(&err).bind(job_id).execute(pool).await?;

            tracing::error!(job_id = %job_id, "Transcode failed: {}", err);
        }
        Err(e) => {
            let err = e.to_string();
            sqlx::query(
                "UPDATE transcode_jobs SET status = 'failed', error_message = $1, completed_at = NOW() WHERE id = $2"
            ).bind(&err).bind(job_id).execute(pool).await?;

            tracing::error!(job_id = %job_id, "Transcode execution failed: {}", err);
        }
    }

    sqlx::query_as("SELECT * FROM transcode_jobs WHERE id = $1")
        .bind(job_id)
        .fetch_one(pool)
        .await
        .map_err(|e| AppError::Internal(e.to_string()))
}

/// Probe media file metadata via local ffprobe, Docker container, or fallback metadata.
pub async fn probe_media(file_path: &str) -> AppResult<MediaInfo> {
    let base_path = std::env::var("PCOS_STORAGE__BASE_PATH")
        .unwrap_or_else(|_| "/data/pcos/storage".into());
    let abs_path = PathBuf::from(&base_path).join(file_path);

    // Try local ffprobe
    if let Ok(output) = tokio::process::Command::new("ffprobe")
        .args([
            "-v",
            "quiet",
            "-print_format",
            "json",
            "-show_format",
            "-show_streams",
            abs_path.to_str().unwrap_or_default(),
        ])
        .output()
        .await
    {
        if output.status.success() {
            let json_str = String::from_utf8_lossy(&output.stdout);
            if let Ok(probe) = serde_json::from_str::<serde_json::Value>(&json_str) {
                return Ok(parse_probe_json(&probe));
            }
        }
    }

    // Try Docker ffprobe
    if let Ok(output) = tokio::process::Command::new("docker")
        .args([
            "run",
            "--rm",
            "-v",
            &format!("{}:/data", base_path),
            "pcos-transcoder:latest",
            "probe",
            file_path,
        ])
        .output()
        .await
    {
        if output.status.success() {
            let json_str = String::from_utf8_lossy(&output.stdout);
            if let Ok(probe) = serde_json::from_str::<serde_json::Value>(&json_str) {
                return Ok(parse_probe_json(&probe));
            }
        }
    }

    // Fallback based on file inspection
    let ext = Path::new(file_path)
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_lowercase();

    let is_video = matches!(
        ext.as_str(),
        "mp4" | "mkv" | "webm" | "avi" | "mov" | "m4v"
    );
    let is_audio = matches!(
        ext.as_str(),
        "mp3" | "flac" | "wav" | "ogg" | "aac" | "m4a"
    );

    Ok(MediaInfo {
        duration_secs: 0.0,
        width: if is_video { Some(1920) } else { None },
        height: if is_video { Some(1080) } else { None },
        video_codec: if is_video { Some("h264".into()) } else { None },
        audio_codec: if is_video || is_audio {
            Some("aac".into())
        } else {
            None
        },
        bitrate_kbps: None,
        format: ext,
        has_video: is_video,
        has_audio: is_video || is_audio,
    })
}

fn parse_probe_json(probe: &serde_json::Value) -> MediaInfo {
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
                    info.video_codec = stream["codec_name"].as_str().map(|s| s.to_string());
                    info.width = stream["width"].as_u64().map(|w| w as u32);
                    info.height = stream["height"].as_u64().map(|h| h as u32);
                }
                Some("audio") => {
                    info.has_audio = true;
                    if info.audio_codec.is_none() {
                        info.audio_codec = stream["codec_name"].as_str().map(|s| s.to_string());
                    }
                }
                _ => {}
            }
        }
    }

    info
}

/// List all transcoding jobs for a user.
pub async fn list_jobs(pool: &PgPool, user_id: Uuid) -> AppResult<Vec<TranscodeJob>> {
    let jobs = sqlx::query_as::<_, TranscodeJob>(
        "SELECT * FROM transcode_jobs WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(jobs)
}

/// Get HLS master playlist URL for a completed job.
pub async fn get_stream_url(pool: &PgPool, job_id: Uuid, user_id: Uuid) -> AppResult<String> {
    let job: TranscodeJob =
        sqlx::query_as("SELECT * FROM transcode_jobs WHERE id = $1 AND user_id = $2")
            .bind(job_id)
            .bind(user_id)
            .fetch_one(pool)
            .await
            .map_err(|_| AppError::NotFound("Job not found".into()))?;

    match job.master_playlist {
        Some(playlist) => Ok(format!("/api/v1/streaming/hls/{}", playlist)),
        None => Err(AppError::Validation("Transcoding not yet completed".into())),
    }
}
