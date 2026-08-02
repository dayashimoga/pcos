use crate::models::*;
use crate::service;
use crate::storage::StorageEngine;
use axum::body::Body;
use axum::extract::{Multipart, Path, Query, State};
use axum::http::{header, StatusCode};
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use serde::Deserialize;
use uuid::Uuid;
use validator::Validate;

fn storage_engine(state: &AppState) -> StorageEngine {
    StorageEngine::new(&state.config.storage)
}

/// POST /api/v1/folders
pub async fn create_folder(
    State(state): State<AppState>, auth: AuthUser, Json(req): Json<CreateFolderRequest>,
) -> Result<impl IntoResponse, AppError> {
    req.validate().map_err(|e| AppError::Validation(e.to_string()))?;
    let result = service::create_folder(state.db.pool(), auth.claims.sub, req).await?;
    Ok((StatusCode::CREATED, Json(result)))
}

/// GET /api/v1/folders (root listing)
pub async fn list_root(
    State(state): State<AppState>, auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let result = service::list_root(state.db.pool(), auth.claims.sub).await?;
    Ok(Json(result))
}

/// GET /api/v1/folders/:id
pub async fn list_folder(
    State(state): State<AppState>, auth: AuthUser, Path(folder_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let result = service::list_folder(state.db.pool(), auth.claims.sub, folder_id).await?;
    Ok(Json(result))
}

/// POST /api/v1/files/upload (multipart form upload)
pub async fn upload_file(
    State(state): State<AppState>, auth: AuthUser, mut multipart: Multipart,
) -> Result<impl IntoResponse, AppError> {
    let storage = storage_engine(&state);
    let mut parent_id: Option<Uuid> = None;
    let mut file_result: Option<FileEntryResponse> = None;

    while let Some(field) = multipart.next_field().await.map_err(|e| AppError::Validation(e.to_string()))? {
        let name = field.name().unwrap_or("").to_string();

        if name == "parent_id" {
            let text = field.text().await.map_err(|e| AppError::Validation(e.to_string()))?;
            if !text.is_empty() {
                parent_id = Some(Uuid::parse_str(&text).map_err(|_| AppError::Validation("Invalid parent_id".to_string()))?);
            }
        } else if name == "file" {
            let filename = field.file_name().unwrap_or("unnamed").to_string();
            let content_type = field.content_type().unwrap_or("application/octet-stream").to_string();
            let data = field.bytes().await.map_err(|e| AppError::Internal(format!("Failed to read upload: {e}")))?;

            file_result = Some(
                service::upload_file(state.db.pool(), &storage, auth.claims.sub, parent_id, &filename, &content_type, &data).await?
            );
        }
    }

    file_result.map(|f| (StatusCode::CREATED, Json(UploadResponse { file: f })))
        .ok_or_else(|| AppError::Validation("No file provided".to_string()))
}

/// POST /api/v1/files/upload/chunk (multipart chunk upload)
pub async fn upload_chunk(
    State(state): State<AppState>, auth: AuthUser, mut multipart: Multipart,
) -> Result<impl IntoResponse, AppError> {
    let storage = storage_engine(&state);
    let mut upload_id: Option<Uuid> = None;
    let mut chunk_index: Option<i32> = None;

    while let Some(field) = multipart.next_field().await.map_err(|e| AppError::Validation(e.to_string()))? {
        let name = field.name().unwrap_or("").to_string();
        match name.as_str() {
            "upload_id" => {
                let text = field.text().await.map_err(|e| AppError::Validation(e.to_string()))?;
                upload_id = Some(Uuid::parse_str(&text).map_err(|_| AppError::Validation("Invalid upload_id".to_string()))?);
            }
            "chunk_index" => {
                let text = field.text().await.map_err(|e| AppError::Validation(e.to_string()))?;
                chunk_index = Some(text.parse().map_err(|_| AppError::Validation("Invalid chunk_index".to_string()))?);
            }
            "chunk" => {
                let uid = upload_id.ok_or_else(|| AppError::Validation("upload_id must be sent before chunk".to_string()))?;
                let idx = chunk_index.ok_or_else(|| AppError::Validation("chunk_index must be sent before chunk".to_string()))?;
                let data = field.bytes().await.map_err(|e| AppError::Internal(format!("Read failed: {e}")))?;
                let result = service::store_chunk(&storage, auth.claims.sub, uid, idx, &data).await?;
                return Ok(Json(result));
            }
            _ => {}
        }
    }

    Err(AppError::Validation("No chunk data provided".to_string()))
}

/// POST /api/v1/files/upload/complete
pub async fn complete_chunked_upload(
    State(state): State<AppState>, auth: AuthUser, Json(req): Json<ChunkedUploadRequest>,
) -> Result<impl IntoResponse, AppError> {
    let storage = storage_engine(&state);
    let result = service::complete_chunked_upload(state.db.pool(), &storage, auth.claims.sub, req).await?;
    Ok((StatusCode::CREATED, Json(UploadResponse { file: result })))
}

/// GET /api/v1/files/:id
pub async fn get_file_meta(
    State(state): State<AppState>, auth: AuthUser, Path(file_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let result = service::get_file_meta(state.db.pool(), auth.claims.sub, file_id).await?;
    Ok(Json(result))
}

/// GET /api/v1/files/:id/download
pub async fn download_file(
    State(state): State<AppState>, auth: AuthUser, Path(file_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let storage = storage_engine(&state);
    let (entry, data) = service::download_file(state.db.pool(), &storage, auth.claims.sub, file_id).await?;

    let content_type = entry.mime_type.unwrap_or_else(|| "application/octet-stream".to_string());

    Ok((
        StatusCode::OK,
        [
            (header::CONTENT_TYPE, content_type),
            (header::CONTENT_DISPOSITION, format!("attachment; filename=\"{}\"", entry.name)),
            (header::CONTENT_LENGTH, data.len().to_string()),
        ],
        data,
    ))
}

/// GET /api/v1/files/:id/preview
pub async fn preview_file(
    State(state): State<AppState>, auth: AuthUser, Path(file_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let storage = storage_engine(&state);
    let (entry, data) = service::download_file(state.db.pool(), &storage, auth.claims.sub, file_id).await?;

    let content_type = entry.mime_type.unwrap_or_else(|| "application/octet-stream".to_string());

    Ok((
        StatusCode::OK,
        [
            (header::CONTENT_TYPE, content_type),
            (header::CONTENT_DISPOSITION, format!("inline; filename=\"{}\"", entry.name)),
        ],
        data,
    ))
}

/// PUT /api/v1/files/:id OR /api/v1/folders/:id (rename)
pub async fn rename_item(
    State(state): State<AppState>, auth: AuthUser, Path(item_id): Path<Uuid>, Json(req): Json<RenameRequest>,
) -> Result<impl IntoResponse, AppError> {
    req.validate().map_err(|e| AppError::Validation(e.to_string()))?;
    let result = service::rename_item(state.db.pool(), auth.claims.sub, item_id, req).await?;
    Ok(Json(result))
}

/// PUT /api/v1/files/:id/move
pub async fn move_item(
    State(state): State<AppState>, auth: AuthUser, Path(item_id): Path<Uuid>, Json(req): Json<MoveRequest>,
) -> Result<impl IntoResponse, AppError> {
    let result = service::move_item(state.db.pool(), auth.claims.sub, item_id, req).await?;
    Ok(Json(result))
}

/// DELETE /api/v1/files/:id OR /api/v1/folders/:id (soft delete → trash)
pub async fn delete_item(
    State(state): State<AppState>, auth: AuthUser, Path(item_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    service::delete_item(state.db.pool(), auth.claims.sub, item_id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// GET /api/v1/trash
pub async fn list_trash(
    State(state): State<AppState>, auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let result = service::list_trash(state.db.pool(), auth.claims.sub).await?;
    Ok(Json(result))
}

/// POST /api/v1/trash/:id/restore
pub async fn restore_from_trash(
    State(state): State<AppState>, auth: AuthUser, Path(item_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let result = service::restore_from_trash(state.db.pool(), auth.claims.sub, item_id).await?;
    Ok(Json(result))
}

/// DELETE /api/v1/trash/:id (permanent delete)
pub async fn permanent_delete(
    State(state): State<AppState>, auth: AuthUser, Path(item_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let storage = storage_engine(&state);
    service::permanent_delete(state.db.pool(), &storage, auth.claims.sub, item_id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// POST /api/v1/trash/empty
pub async fn empty_trash(
    State(state): State<AppState>, auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let storage = storage_engine(&state);
    let count = service::empty_trash(state.db.pool(), &storage, auth.claims.sub).await?;
    Ok(Json(serde_json::json!({ "deleted": count })))
}

/// GET /api/v1/storage/stats
pub async fn storage_stats(
    State(state): State<AppState>, auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let result = service::storage_stats(state.db.pool(), auth.claims.sub).await?;
    Ok(Json(result))
}
