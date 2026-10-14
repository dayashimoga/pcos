//! PCOS Resumable Transfers Protocol
//!
//! Provides chunked, resumable, range-compatible transfer sessions for large files (up to 100GB).
//! Mirrors the Edge Control Plane Resumable Transfer protocol for seamless local/self-hosted parity.

use crate::service::check_storage_quota;
use crate::storage::StorageEngine;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use base64::Engine;
use chrono::Utc;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::{AppError, AppResult};
use pcos_common::AppState;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Deserialize)]
pub struct ResumableInitRequest {
    pub name: String,
    pub size_bytes: i64,
    pub sha256_hash: Option<String>,
    pub storage_node_id: Option<String>,
    pub parent_id: Option<Uuid>,
    pub mime_type: Option<String>,
}

#[derive(Serialize)]
pub struct ResumableInitResponse {
    pub transfer_id: String,
    pub name: String,
    pub total_bytes: i64,
    pub chunk_size: usize,
    pub uploaded_bytes: i64,
    pub sha256_hash: String,
    pub created_at: String,
}

#[derive(Deserialize)]
pub struct ResumableChunkRequest {
    pub offset: i64,
    pub data_base64: String,
}

#[derive(Serialize)]
pub struct ResumableChunkResponse {
    pub transfer_id: String,
    pub offset: i64,
    pub bytes_written: usize,
    pub success: bool,
}

#[derive(Serialize)]
pub struct ResumableStatusResponse {
    pub transfer_id: String,
    pub name: String,
    pub total_bytes: i64,
    pub sha256_hash: Option<String>,
    pub status: String,
}

#[derive(Deserialize)]
pub struct ResumableFinalizeRequest {
    pub sha256_hash: Option<String>,
}

#[derive(Serialize)]
pub struct ResumableFinalizeResponse {
    pub success: bool,
    pub file_id: String,
    pub name: String,
    pub size_bytes: i64,
    pub sha256_hash: String,
}

/// POST /api/v1/transfers/resumable/init
pub async fn init_transfer(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<ResumableInitRequest>,
) -> AppResult<impl IntoResponse> {
    if req.name.trim().is_empty() {
        return Err(AppError::Validation("name is required".into()));
    }
    if req.size_bytes < 0 {
        return Err(AppError::Validation("size_bytes must be non-negative".into()));
    }

    // Verify storage quota before creating transfer session
    check_storage_quota(state.db.pool(), auth.claims.sub, req.size_bytes).await?;

    let file_id = Uuid::new_v4();
    let transfer_id = format!("xfer_{}", file_id);
    let now = Utc::now();
    let mime = req
        .mime_type
        .unwrap_or_else(|| "application/octet-stream".to_string());
    let sha256 = req.sha256_hash.unwrap_or_default();

    sqlx::query(
        r#"INSERT INTO file_entries (id, user_id, parent_id, name, entry_type, mime_type, size_bytes, sha256_hash, storage_path, is_trashed, is_favorite, created_at, updated_at)
           VALUES ($1, $2, $3, $4, 'file', $5, $6, $7, 'resumable_transfer', false, false, $8, $8)"#,
    )
    .bind(file_id)
    .bind(auth.claims.sub)
    .bind(req.parent_id)
    .bind(&req.name)
    .bind(&mime)
    .bind(req.size_bytes)
    .bind(&sha256)
    .bind(now)
    .execute(state.db.pool())
    .await?;

    Ok((
        StatusCode::CREATED,
        Json(ResumableInitResponse {
            transfer_id,
            name: req.name,
            total_bytes: req.size_bytes,
            chunk_size: 2 * 1024 * 1024,
            uploaded_bytes: 0,
            sha256_hash: sha256,
            created_at: now.to_rfc3339(),
        }),
    ))
}

/// POST /api/v1/transfers/resumable/:id/chunk
pub async fn write_chunk(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(transfer_id): Path<String>,
    Json(req): Json<ResumableChunkRequest>,
) -> AppResult<impl IntoResponse> {
    let file_uuid = parse_transfer_uuid(&transfer_id)?;

    // Verify file entry belongs to user
    let _entry: (Uuid,) = sqlx::query_as(
        "SELECT id FROM file_entries WHERE id = $1 AND user_id = $2 AND storage_path = 'resumable_transfer'",
    )
    .bind(file_uuid)
    .bind(auth.claims.sub)
    .fetch_one(state.db.pool())
    .await
    .map_err(|_| AppError::NotFound("Transfer session not found or already finalized".into()))?;

    let chunk_bytes = base64::engine::general_purpose::STANDARD
        .decode(req.data_base64.trim())
        .map_err(|e| AppError::Validation(format!("Invalid base64 payload: {e}")))?;

    let storage = StorageEngine::new(&state.config.storage);
    let chunk_index = (req.offset / (2 * 1024 * 1024)) as i32;

    storage
        .store_chunk(auth.claims.sub, file_uuid, chunk_index, &chunk_bytes)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to store chunk: {e}")))?;

    sqlx::query("UPDATE file_entries SET updated_at = NOW() WHERE id = $1")
        .bind(file_uuid)
        .execute(state.db.pool())
        .await?;

    Ok(Json(ResumableChunkResponse {
        transfer_id,
        offset: req.offset,
        bytes_written: chunk_bytes.len(),
        success: true,
    }))
}

/// GET /api/v1/transfers/resumable/:id/status
pub async fn get_status(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(transfer_id): Path<String>,
) -> AppResult<impl IntoResponse> {
    let file_uuid = parse_transfer_uuid(&transfer_id)?;

    let entry: (String, i64, Option<String>, String) = sqlx::query_as(
        "SELECT name, size_bytes, sha256_hash, storage_path FROM file_entries WHERE id = $1 AND user_id = $2",
    )
    .bind(file_uuid)
    .bind(auth.claims.sub)
    .fetch_one(state.db.pool())
    .await
    .map_err(|_| AppError::NotFound("Transfer session not found".into()))?;

    let status = if entry.3 == "resumable_transfer" {
        "in_progress".to_string()
    } else {
        "completed".to_string()
    };

    Ok(Json(ResumableStatusResponse {
        transfer_id,
        name: entry.0,
        total_bytes: entry.1,
        sha256_hash: entry.2,
        status,
    }))
}

/// POST /api/v1/transfers/resumable/:id/finalize
pub async fn finalize_transfer(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(transfer_id): Path<String>,
    Json(req): Json<ResumableFinalizeRequest>,
) -> AppResult<impl IntoResponse> {
    let file_uuid = parse_transfer_uuid(&transfer_id)?;

    let entry: (String, i64, Option<String>) = sqlx::query_as(
        "SELECT name, size_bytes, sha256_hash FROM file_entries WHERE id = $1 AND user_id = $2",
    )
    .bind(file_uuid)
    .bind(auth.claims.sub)
    .fetch_one(state.db.pool())
    .await
    .map_err(|_| AppError::NotFound("Transfer session not found".into()))?;

    let final_sha256 = req
        .sha256_hash
        .or(entry.2)
        .unwrap_or_else(|| "verified".to_string());

    let final_storage_path = format!("{}/{}", auth.claims.sub, file_uuid);

    sqlx::query("UPDATE file_entries SET storage_path = $1, sha256_hash = $2, updated_at = NOW() WHERE id = $3")
        .bind(&final_storage_path)
        .bind(&final_sha256)
        .bind(file_uuid)
        .execute(state.db.pool())
        .await?;

    Ok(Json(ResumableFinalizeResponse {
        success: true,
        file_id: file_uuid.to_string(),
        name: entry.0,
        size_bytes: entry.1,
        sha256_hash: final_sha256,
    }))
}

fn parse_transfer_uuid(id: &str) -> AppResult<Uuid> {
    let clean = id.trim_start_matches("xfer_");
    Uuid::parse_str(clean).map_err(|_| AppError::Validation(format!("Invalid transfer ID: {id}")))
}
