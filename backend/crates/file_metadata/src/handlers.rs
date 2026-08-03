use crate::models::*;
use crate::service;
use crate::storage::StorageEngine;
use axum::extract::{Multipart, Path, State};
use axum::http::{header, StatusCode};
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use uuid::Uuid;
use validator::Validate;

fn storage_engine(state: &AppState) -> StorageEngine {
    StorageEngine::new(&state.config.storage)
}

/// POST /api/v1/folders
pub async fn create_folder(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<CreateFolderRequest>,
) -> Result<impl IntoResponse, AppError> {
    req.validate()
        .map_err(|e| AppError::Validation(e.to_string()))?;
    let result = service::create_folder(state.db.pool(), auth.claims.sub, req).await?;
    Ok((StatusCode::CREATED, Json(result)))
}

/// GET /api/v1/folders (root listing)
pub async fn list_root(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let result = service::list_root(state.db.pool(), auth.claims.sub).await?;
    Ok(Json(result))
}

/// GET /api/v1/folders/:id
pub async fn list_folder(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(folder_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let result = service::list_folder(state.db.pool(), auth.claims.sub, folder_id).await?;
    Ok(Json(result))
}

/// POST /api/v1/files/upload (multipart form upload)
pub async fn upload_file(
    State(state): State<AppState>,
    auth: AuthUser,
    mut multipart: Multipart,
) -> Result<impl IntoResponse, AppError> {
    let storage = storage_engine(&state);
    let mut parent_id: Option<Uuid> = None;
    let mut file_result: Option<FileEntryResponse> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| AppError::Validation(e.to_string()))?
    {
        let name = field.name().unwrap_or("").to_string();

        if name == "parent_id" {
            let text = field
                .text()
                .await
                .map_err(|e| AppError::Validation(e.to_string()))?;
            if !text.is_empty() {
                parent_id = Some(
                    Uuid::parse_str(&text)
                        .map_err(|_| AppError::Validation("Invalid parent_id".to_string()))?,
                );
            }
        } else if name == "file" {
            let filename = field.file_name().unwrap_or("unnamed").to_string();
            let content_type = field
                .content_type()
                .unwrap_or("application/octet-stream")
                .to_string();
            let data = field
                .bytes()
                .await
                .map_err(|e| AppError::Internal(format!("Failed to read upload: {e}")))?;

            file_result = Some(
                service::upload_file(
                    state.db.pool(),
                    &storage,
                    auth.claims.sub,
                    parent_id,
                    &filename,
                    &content_type,
                    &data,
                )
                .await?,
            );
        }
    }

    file_result
        .map(|f| (StatusCode::CREATED, Json(UploadResponse { file: f })))
        .ok_or_else(|| AppError::Validation("No file provided".to_string()))
}

/// POST /api/v1/files/upload/chunk (multipart chunk upload)
pub async fn upload_chunk(
    State(state): State<AppState>,
    auth: AuthUser,
    mut multipart: Multipart,
) -> Result<impl IntoResponse, AppError> {
    let storage = storage_engine(&state);
    let mut upload_id: Option<Uuid> = None;
    let mut chunk_index: Option<i32> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| AppError::Validation(e.to_string()))?
    {
        let name = field.name().unwrap_or("").to_string();
        match name.as_str() {
            "upload_id" => {
                let text = field
                    .text()
                    .await
                    .map_err(|e| AppError::Validation(e.to_string()))?;
                upload_id = Some(
                    Uuid::parse_str(&text)
                        .map_err(|_| AppError::Validation("Invalid upload_id".to_string()))?,
                );
            }
            "chunk_index" => {
                let text = field
                    .text()
                    .await
                    .map_err(|e| AppError::Validation(e.to_string()))?;
                chunk_index = Some(
                    text.parse()
                        .map_err(|_| AppError::Validation("Invalid chunk_index".to_string()))?,
                );
            }
            "chunk" => {
                let uid = upload_id.ok_or_else(|| {
                    AppError::Validation("upload_id must be sent before chunk".to_string())
                })?;
                let idx = chunk_index.ok_or_else(|| {
                    AppError::Validation("chunk_index must be sent before chunk".to_string())
                })?;
                let data = field
                    .bytes()
                    .await
                    .map_err(|e| AppError::Internal(format!("Read failed: {e}")))?;
                let result =
                    service::store_chunk(&storage, auth.claims.sub, uid, idx, &data).await?;
                return Ok(Json(result));
            }
            _ => {}
        }
    }

    Err(AppError::Validation("No chunk data provided".to_string()))
}

/// POST /api/v1/files/upload/complete
pub async fn complete_chunked_upload(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<ChunkedUploadRequest>,
) -> Result<impl IntoResponse, AppError> {
    let storage = storage_engine(&state);
    let result =
        service::complete_chunked_upload(state.db.pool(), &storage, auth.claims.sub, req).await?;
    Ok((StatusCode::CREATED, Json(UploadResponse { file: result })))
}

/// GET /api/v1/files/:id
pub async fn get_file_meta(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(file_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let result = service::get_file_meta(state.db.pool(), auth.claims.sub, file_id).await?;
    Ok(Json(result))
}

/// GET /api/v1/files/:id/download — supports HTTP Range requests for resume
pub async fn download_file(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(file_id): Path<Uuid>,
    headers: axum::http::HeaderMap,
) -> Result<impl IntoResponse, AppError> {
    let storage = storage_engine(&state);
    let (entry, data) =
        service::download_file(state.db.pool(), &storage, auth.claims.sub, file_id).await?;

    let content_type = entry
        .mime_type
        .unwrap_or_else(|| "application/octet-stream".to_string());
    let total_size = data.len();

    // Parse Range header if present
    if let Some(range_header) = headers.get(header::RANGE) {
        if let Ok(range_str) = range_header.to_str() {
            if let Some(range) = parse_range(range_str, total_size) {
                let (start, end) = range;
                let slice = data[start..=end].to_vec();
                let content_length = end - start + 1;

                return Ok((
                    StatusCode::PARTIAL_CONTENT,
                    [
                        (header::CONTENT_TYPE, content_type),
                        (
                            header::CONTENT_DISPOSITION,
                            format!("attachment; filename=\"{}\"", entry.name),
                        ),
                        (header::CONTENT_LENGTH, content_length.to_string()),
                        (
                            header::CONTENT_RANGE,
                            format!("bytes {}-{}/{}", start, end, total_size),
                        ),
                        (header::ACCEPT_RANGES, "bytes".to_string()),
                    ],
                    slice,
                )
                    .into_response());
            }
        }
    }

    // No Range header — return full file
    Ok((
        StatusCode::OK,
        [
            (header::CONTENT_TYPE, content_type),
            (
                header::CONTENT_DISPOSITION,
                format!("attachment; filename=\"{}\"", entry.name),
            ),
            (header::CONTENT_LENGTH, total_size.to_string()),
            (header::ACCEPT_RANGES, "bytes".to_string()),
            // ETag for caching
            (
                header::ETAG,
                format!("\"{}\"", entry.sha256_hash.unwrap_or_default()),
            ),
        ],
        data,
    )
        .into_response())
}

/// Parse HTTP Range header "bytes=START-END"
fn parse_range(range: &str, total: usize) -> Option<(usize, usize)> {
    let range = range.strip_prefix("bytes=")?;
    let parts: Vec<&str> = range.split('-').collect();
    if parts.len() != 2 {
        return None;
    }

    let start = parts[0].parse::<usize>().ok()?;
    let end = if parts[1].is_empty() {
        total - 1
    } else {
        parts[1].parse::<usize>().ok()?
    };

    if start > end || end >= total {
        return None;
    }
    Some((start, end))
}

/// GET /api/v1/files/:id/preview
pub async fn preview_file(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(file_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let storage = storage_engine(&state);
    let (entry, data) =
        service::download_file(state.db.pool(), &storage, auth.claims.sub, file_id).await?;

    let content_type = entry
        .mime_type
        .unwrap_or_else(|| "application/octet-stream".to_string());

    Ok((
        StatusCode::OK,
        [
            (header::CONTENT_TYPE, content_type),
            (
                header::CONTENT_DISPOSITION,
                format!("inline; filename=\"{}\"", entry.name),
            ),
        ],
        data,
    ))
}

/// PUT /api/v1/files/:id OR /api/v1/folders/:id (rename)
pub async fn rename_item(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(item_id): Path<Uuid>,
    Json(req): Json<RenameRequest>,
) -> Result<impl IntoResponse, AppError> {
    req.validate()
        .map_err(|e| AppError::Validation(e.to_string()))?;
    let result = service::rename_item(state.db.pool(), auth.claims.sub, item_id, req).await?;
    Ok(Json(result))
}

/// PUT /api/v1/files/:id/move
pub async fn move_item(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(item_id): Path<Uuid>,
    Json(req): Json<MoveRequest>,
) -> Result<impl IntoResponse, AppError> {
    let result = service::move_item(state.db.pool(), auth.claims.sub, item_id, req).await?;
    Ok(Json(result))
}

/// DELETE /api/v1/files/:id OR /api/v1/folders/:id (soft delete → trash)
pub async fn delete_item(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(item_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    service::delete_item(state.db.pool(), auth.claims.sub, item_id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// GET /api/v1/trash
pub async fn list_trash(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let result = service::list_trash(state.db.pool(), auth.claims.sub).await?;
    Ok(Json(result))
}

/// POST /api/v1/trash/:id/restore
pub async fn restore_from_trash(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(item_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let result = service::restore_from_trash(state.db.pool(), auth.claims.sub, item_id).await?;
    Ok(Json(result))
}

/// DELETE /api/v1/trash/:id (permanent delete)
pub async fn permanent_delete(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(item_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let storage = storage_engine(&state);
    service::permanent_delete(state.db.pool(), &storage, auth.claims.sub, item_id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// POST /api/v1/trash/empty
pub async fn empty_trash(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let storage = storage_engine(&state);
    let count = service::empty_trash(state.db.pool(), &storage, auth.claims.sub).await?;
    Ok(Json(serde_json::json!({ "deleted": count })))
}

/// GET /api/v1/storage/stats
pub async fn storage_stats(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let result = service::storage_stats(state.db.pool(), auth.claims.sub).await?;
    Ok(Json(result))
}
