//! Streaming API handlers.

use axum::extract::{Path, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use serde::Deserialize;
use std::path::PathBuf;
use tokio::fs;
use uuid::Uuid;

use crate::service::{self, TranscodeProfile};

#[derive(Debug, Deserialize)]
pub struct TranscodeRequest {
    pub file_id: Uuid,
    pub profile: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct PlaybackTokenRequest {
    pub device_id: Option<Uuid>,
}

/// POST /api/v1/streaming/transcode — Queue a transcoding job.
pub async fn transcode(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<TranscodeRequest>,
) -> Result<impl IntoResponse, AppError> {
    let profile = match req.profile.as_deref() {
        Some("audio-only") => TranscodeProfile::AudioOnly,
        Some("thumbnail") => TranscodeProfile::Thumbnail,
        _ => TranscodeProfile::Adaptive,
    };

    // Look up file path from DB
    let file: (String,) =
        sqlx::query_as("SELECT storage_path FROM file_entries WHERE id = $1 AND user_id = $2")
            .bind(req.file_id)
            .bind(auth.claims.sub)
            .fetch_one(state.db.pool())
            .await
            .map_err(|_| AppError::NotFound("File not found".into()))?;

    let job = service::queue_transcode(
        state.db.pool(),
        req.file_id,
        auth.claims.sub,
        &file.0,
        profile,
    )
    .await?;

    // Spawn background transcoding
    let pool = state.db.pool().clone();
    let job_id = job.id;
    tokio::spawn(async move {
        if let Err(e) = service::execute_transcode(&pool, job_id).await {
            tracing::error!(job_id = %job_id, "Background transcode failed: {e}");
        }
    });

    Ok((
        axum::http::StatusCode::ACCEPTED,
        Json(serde_json::json!({
            "job_id": job.id,
            "status": "pending",
            "profile": job.profile,
            "message": "Transcoding job queued"
        })),
    ))
}

/// GET /api/v1/streaming/jobs — List transcoding jobs.
pub async fn list_jobs(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let jobs = service::list_jobs(state.db.pool(), auth.claims.sub).await?;
    Ok(Json(
        serde_json::json!({ "jobs": jobs, "total": jobs.len() }),
    ))
}

/// GET /api/v1/streaming/jobs/:id — Get job status.
pub async fn get_job(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(job_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let job: service::TranscodeJob =
        sqlx::query_as("SELECT * FROM transcode_jobs WHERE id = $1 AND user_id = $2")
            .bind(job_id)
            .bind(auth.claims.sub)
            .fetch_one(state.db.pool())
            .await
            .map_err(|_| AppError::NotFound("Job not found".into()))?;

    Ok(Json(serde_json::json!(job)))
}

/// GET /api/v1/streaming/stream/:id — Get HLS stream URL.
pub async fn stream_url(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(job_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let url = service::get_stream_url(state.db.pool(), job_id, auth.claims.sub).await?;
    Ok(Json(serde_json::json!({
        "stream_url": url,
        "type": "application/x-mpegURL",
        "protocol": "HLS"
    })))
}

/// POST /api/v1/streaming/probe/:file_id — Probe media metadata.
pub async fn probe(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(file_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let file: (String,) =
        sqlx::query_as("SELECT storage_path FROM file_entries WHERE id = $1 AND user_id = $2")
            .bind(file_id)
            .bind(auth.claims.sub)
            .fetch_one(state.db.pool())
            .await
            .map_err(|_| AppError::NotFound("File not found".into()))?;

    let info = service::probe_media(&file.0).await?;
    Ok(Json(serde_json::json!(info)))
}

/// POST /api/v1/streaming/token/:file_id — Generate short-lived playback token.
pub async fn generate_playback_token(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(file_id): Path<Uuid>,
    Json(req): Json<PlaybackTokenRequest>,
) -> Result<impl IntoResponse, AppError> {
    // Verify file exists and user has ownership
    let _file: (Uuid,) = sqlx::query_as(
        "SELECT id FROM file_entries WHERE id = $1 AND user_id = $2 AND is_trashed = false",
    )
    .bind(file_id)
    .bind(auth.claims.sub)
    .fetch_one(state.db.pool())
    .await
    .map_err(|_| AppError::NotFound("File not found".into()))?;

    let (token, exp) = service::create_playback_token(
        auth.claims.sub,
        file_id,
        req.device_id,
        &state.config.auth.jwt_secret,
    )?;

    Ok(Json(serde_json::json!({
        "token": token,
        "expires_at": exp,
        "stream_url": format!("/api/v1/streaming/play/{}", token),
    })))
}

/// GET /api/v1/streaming/play/:token — Direct media stream via playback token (supports Range/206).
pub async fn play_with_token(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(token): Path<String>,
) -> Result<Response, AppError> {
    let claims = service::verify_playback_token(&token, &state.config.auth.jwt_secret)?;

    let file: Option<(String, Option<String>, Option<String>)> = sqlx::query_as(
        "SELECT name, mime_type, storage_path FROM file_entries WHERE id = $1 AND user_id = $2 AND is_trashed = false"
    )
    .bind(claims.file_id)
    .bind(claims.sub)
    .fetch_optional(state.db.pool())
    .await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    let (name, mime, storage_path) = match file {
        Some(f) => f,
        None => return Ok(StatusCode::NOT_FOUND.into_response()),
    };

    let base_path =
        std::env::var("PCOS_STORAGE__BASE_PATH").unwrap_or_else(|_| "/data/pcos/storage".into());

    let abs_path = match storage_path {
        Some(p) => PathBuf::from(base_path).join(p),
        None => return Ok(StatusCode::NOT_FOUND.into_response()),
    };

    let data = fs::read(&abs_path)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to read media: {e}")))?;

    let total_size = data.len();
    let content_type = mime.unwrap_or_else(|| "application/octet-stream".to_string());

    // Check Range header
    if let Some(range_header) = headers.get(header::RANGE).and_then(|v| v.to_str().ok()) {
        if let Some(range) = range_header.strip_prefix("bytes=") {
            let parts: Vec<&str> = range.split('-').collect();
            let start = parts[0].parse::<usize>().unwrap_or(0);
            let end = parts
                .get(1)
                .and_then(|s| s.parse::<usize>().ok())
                .unwrap_or(total_size.saturating_sub(1));

            if start < total_size && start <= end {
                let end = end.min(total_size.saturating_sub(1));
                let slice = data[start..=end].to_vec();
                let length = end - start + 1;

                return Ok(Response::builder()
                    .status(StatusCode::PARTIAL_CONTENT)
                    .header(header::CONTENT_TYPE, content_type)
                    .header(header::CONTENT_LENGTH, length.to_string())
                    .header(
                        header::CONTENT_RANGE,
                        format!("bytes {}-{}/{}", start, end, total_size),
                    )
                    .header(header::ACCEPT_RANGES, "bytes")
                    .header(
                        header::CONTENT_DISPOSITION,
                        format!("inline; filename=\"{}\"", name),
                    )
                    .body(axum::body::Body::from(slice))
                    .expect("valid 206 response"));
            }
        }
    }

    Ok(Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, content_type)
        .header(header::CONTENT_LENGTH, total_size.to_string())
        .header(header::ACCEPT_RANGES, "bytes")
        .header(
            header::CONTENT_DISPOSITION,
            format!("inline; filename=\"{}\"", name),
        )
        .body(axum::body::Body::from(data))
        .expect("valid 200 response"))
}
