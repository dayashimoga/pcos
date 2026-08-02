use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct FileVersion {
    pub id: Uuid,
    pub file_entry_id: Uuid,
    pub version_number: i32,
    pub size_bytes: i64,
    pub sha256_hash: Option<String>,
    pub storage_path: String,
    pub created_by: Uuid,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// GET /api/v1/files/:id/versions — list all versions of a file
pub async fn list_versions(
    State(state): State<AppState>, auth: AuthUser, Path(file_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    // Verify ownership
    sqlx::query("SELECT id FROM file_entries WHERE id = $1 AND user_id = $2")
        .bind(file_id).bind(auth.claims.sub)
        .fetch_optional(state.db.pool()).await?
        .ok_or_else(|| AppError::NotFound("File not found".to_string()))?;

    let versions = sqlx::query_as::<_, FileVersion>(
        "SELECT * FROM file_versions WHERE file_entry_id = $1 ORDER BY version_number DESC"
    ).bind(file_id).fetch_all(state.db.pool()).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(Json(serde_json::json!({
        "file_id": file_id,
        "versions": versions,
        "total": versions.len(),
    })))
}

/// POST /api/v1/files/:id/versions/:version/restore — restore a specific version
pub async fn restore_version(
    State(state): State<AppState>, auth: AuthUser,
    Path((file_id, version_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, AppError> {
    let pool = state.db.pool();

    // Verify ownership
    sqlx::query("SELECT id FROM file_entries WHERE id = $1 AND user_id = $2")
        .bind(file_id).bind(auth.claims.sub)
        .fetch_optional(pool).await?
        .ok_or_else(|| AppError::NotFound("File not found".to_string()))?;

    // Get the version to restore
    let version = sqlx::query_as::<_, FileVersion>(
        "SELECT * FROM file_versions WHERE id = $1 AND file_entry_id = $2"
    ).bind(version_id).bind(file_id).fetch_optional(pool).await?
    .ok_or_else(|| AppError::NotFound("Version not found".to_string()))?;

    // Update the current file entry to point to this version's storage
    sqlx::query(
        "UPDATE file_entries SET storage_path = $1, size_bytes = $2, sha256_hash = $3, updated_at = NOW() WHERE id = $4"
    ).bind(&version.storage_path).bind(version.size_bytes).bind(&version.sha256_hash).bind(file_id)
    .execute(pool).await?;

    Ok(Json(serde_json::json!({
        "message": "Version restored",
        "restored_version": version.version_number,
    })))
}

/// GET /api/v1/files/:id/versions/:version/download — download a specific version
pub async fn download_version(
    State(state): State<AppState>, auth: AuthUser,
    Path((file_id, version_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, AppError> {
    let pool = state.db.pool();

    // Verify ownership
    let file: (String, Option<String>) = sqlx::query_as(
        "SELECT name, mime_type FROM file_entries WHERE id = $1 AND user_id = $2"
    ).bind(file_id).bind(auth.claims.sub).fetch_optional(pool).await?
    .ok_or_else(|| AppError::NotFound("File not found".to_string()))?;

    let version = sqlx::query_as::<_, FileVersion>(
        "SELECT * FROM file_versions WHERE id = $1 AND file_entry_id = $2"
    ).bind(version_id).bind(file_id).fetch_optional(pool).await?
    .ok_or_else(|| AppError::NotFound("Version not found".to_string()))?;

    let storage = crate::storage::StorageEngine::new(&state.config.storage);
    let data = storage.read_file(&version.storage_path).await
        .map_err(|e| AppError::Internal(format!("Read failed: {e}")))?;

    let content_type = file.1.unwrap_or_else(|| "application/octet-stream".to_string());

    Ok((
        StatusCode::OK,
        [
            (axum::http::header::CONTENT_TYPE, content_type),
            (axum::http::header::CONTENT_DISPOSITION, format!("attachment; filename=\"v{}_{}\"", version.version_number, file.0)),
            (axum::http::header::CONTENT_LENGTH, data.len().to_string()),
        ],
        data,
    ))
}
