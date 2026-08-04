use crate::models::*;
use crate::service;
use axum::extract::{Path, Query, State};
use axum::http::{header, StatusCode};
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use serde::Deserialize;
use uuid::Uuid;
use validator::Validate;

pub async fn create_share(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<CreateShareRequest>,
) -> Result<impl IntoResponse, AppError> {
    req.validate()
        .map_err(|e| AppError::Validation(e.to_string()))?;
    let share = service::create_share(state.db.pool(), auth.claims.sub, req).await?;
    let base_url = std::env::var("PCOS_PUBLIC_URL").unwrap_or_default();
    Ok((StatusCode::CREATED, Json(share.to_response(&base_url))))
}

pub async fn list_shares(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let shares = service::list_shares(state.db.pool(), auth.claims.sub).await?;
    let base_url = std::env::var("PCOS_PUBLIC_URL").unwrap_or_default();
    let responses: Vec<ShareResponse> = shares.iter().map(|s| s.to_response(&base_url)).collect();
    Ok(Json(
        serde_json::json!({ "shares": responses, "total": responses.len() }),
    ))
}

pub async fn get_share(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let share = service::get_share(state.db.pool(), auth.claims.sub, id).await?;
    let base_url = std::env::var("PCOS_PUBLIC_URL").unwrap_or_default();
    Ok(Json(share.to_response(&base_url)))
}

pub async fn update_share(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateShareRequest>,
) -> Result<impl IntoResponse, AppError> {
    let share = service::update_share(state.db.pool(), auth.claims.sub, id, req).await?;
    let base_url = std::env::var("PCOS_PUBLIC_URL").unwrap_or_default();
    Ok(Json(share.to_response(&base_url)))
}

pub async fn delete_share(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    service::delete_share(state.db.pool(), auth.claims.sub, id).await?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Deserialize)]
pub struct SharedAccessQuery {
    pub password: Option<String>,
}

pub async fn access_shared(
    State(state): State<AppState>,
    Path(token): Path<String>,
    Query(q): Query<SharedAccessQuery>,
) -> Result<impl IntoResponse, AppError> {
    let info = service::access_shared(state.db.pool(), &token, q.password.as_deref()).await?;
    Ok(Json(info))
}

pub async fn download_shared(
    State(state): State<AppState>,
    Path(token): Path<String>,
) -> Result<impl IntoResponse, AppError> {
    let pool = state.db.pool();

    // Validate share link
    let share = sqlx::query_as::<_, ShareLink>(
        "SELECT * FROM share_links WHERE token = $1 AND is_active = true AND permission = 'download'"
    ).bind(&token).fetch_optional(pool).await?
        .ok_or_else(|| AppError::NotFound("Share not found or no download permission".to_string()))?;

    // Check expiration
    if let Some(exp) = share.expires_at {
        if chrono::Utc::now() > exp {
            return Err(AppError::Forbidden("Share link expired".to_string()));
        }
    }
    // Check download limit
    if let Some(max) = share.max_downloads {
        if share.download_count >= max {
            return Err(AppError::Forbidden("Download limit reached".to_string()));
        }
    }

    // Get file info using FromRow struct
    #[derive(sqlx::FromRow)]
    struct FileInfo {
        name: String,
        storage_path: Option<String>,
        mime_type: Option<String>,
    }

    let file = sqlx::query_as::<_, FileInfo>(
        "SELECT name, storage_path, mime_type FROM file_entries WHERE id = $1",
    )
    .bind(share.file_entry_id)
    .fetch_one(pool)
    .await?;

    let path = file
        .storage_path
        .ok_or_else(|| AppError::Internal("File has no storage path".to_string()))?;

    // Read file from storage
    let storage = pcos_file_metadata::storage::StorageEngine::new(&state.config.storage);
    let data = storage
        .read_file(&path)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to read file: {e}")))?;

    // Increment download count
    sqlx::query("UPDATE share_links SET download_count = download_count + 1 WHERE id = $1")
        .bind(share.id)
        .execute(pool)
        .await?;

    let content_type = file
        .mime_type
        .unwrap_or_else(|| "application/octet-stream".to_string());

    Ok((
        [
            (header::CONTENT_TYPE, content_type),
            (
                header::CONTENT_DISPOSITION,
                format!("attachment; filename=\"{}\"", file.name),
            ),
            (header::CONTENT_LENGTH, data.len().to_string()),
        ],
        data,
    ))
}
