//! Streaming API handlers.

use axum::extract::{Path, State};
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use serde::Deserialize;
use uuid::Uuid;

use crate::service::{self, TranscodeProfile};

#[derive(Debug, Deserialize)]
pub struct TranscodeRequest {
    pub file_id: Uuid,
    pub profile: Option<String>,
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
    let file: (String,) = sqlx::query_as(
        "SELECT storage_path FROM file_entries WHERE id = $1 AND user_id = $2"
    )
    .bind(req.file_id).bind(auth.claims.sub)
    .fetch_one(&*state.db)
    .await
    .map_err(|_| AppError::NotFound("File not found".into()))?;

    let job = service::queue_transcode(&state.db, req.file_id, auth.claims.sub, &file.0, profile).await?;

    // Spawn background transcoding
    let pool = state.db.clone();
    let job_id = job.id;
    tokio::spawn(async move {
        if let Err(e) = service::execute_transcode(&pool, job_id).await {
            tracing::error!(job_id = %job_id, "Background transcode failed: {e}");
        }
    });

    Ok((axum::http::StatusCode::ACCEPTED, Json(serde_json::json!({
        "job_id": job.id,
        "status": "pending",
        "profile": job.profile,
        "message": "Transcoding job queued"
    }))))
}

/// GET /api/v1/streaming/jobs — List transcoding jobs.
pub async fn list_jobs(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let jobs = service::list_jobs(&state.db, auth.claims.sub).await?;
    Ok(Json(serde_json::json!({ "jobs": jobs, "total": jobs.len() })))
}

/// GET /api/v1/streaming/jobs/:id — Get job status.
pub async fn get_job(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(job_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let job: service::TranscodeJob = sqlx::query_as(
        "SELECT * FROM transcode_jobs WHERE id = $1 AND user_id = $2"
    )
    .bind(job_id).bind(auth.claims.sub)
    .fetch_one(&*state.db)
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
    let url = service::get_stream_url(&state.db, job_id, auth.claims.sub).await?;
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
    let file: (String,) = sqlx::query_as(
        "SELECT storage_path FROM file_entries WHERE id = $1 AND user_id = $2"
    )
    .bind(file_id).bind(auth.claims.sub)
    .fetch_one(&*state.db)
    .await
    .map_err(|_| AppError::NotFound("File not found".into()))?;

    let info = service::probe_media(&file.0).await?;
    Ok(Json(serde_json::json!(info)))
}
