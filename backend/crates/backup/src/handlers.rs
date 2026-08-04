use crate::service;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use uuid::Uuid;

pub async fn list_backups(
    State(s): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let b = service::list_backups(s.db.pool(), auth.claims.sub).await?;
    Ok(Json(serde_json::json!({ "backups": b, "total": b.len() })))
}
pub async fn create_backup(
    State(s): State<AppState>,
    auth: AuthUser,
    Json(req): Json<service::CreateBackupRequest>,
) -> Result<impl IntoResponse, AppError> {
    let b = service::create_backup(s.db.pool(), auth.claims.sub, req).await?;
    Ok((StatusCode::CREATED, Json(b)))
}
pub async fn get_backup(
    State(s): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    Ok(Json(
        service::get_backup(s.db.pool(), auth.claims.sub, id).await?,
    ))
}
pub async fn delete_backup(
    State(s): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    service::delete_backup(s.db.pool(), auth.claims.sub, id).await?;
    Ok(StatusCode::NO_CONTENT)
}
pub async fn restore_backup(
    State(s): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let msg = service::restore_backup(s.db.pool(), auth.claims.sub, id).await?;
    Ok(Json(serde_json::json!({ "message": msg })))
}
pub async fn list_schedules(
    State(s): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    Ok(Json(
        serde_json::json!({ "schedules": service::list_schedules(s.db.pool(), auth.claims.sub).await? }),
    ))
}
pub async fn create_schedule(
    State(s): State<AppState>,
    auth: AuthUser,
    Json(req): Json<service::CreateScheduleRequest>,
) -> Result<impl IntoResponse, AppError> {
    Ok((
        StatusCode::CREATED,
        Json(service::create_schedule(s.db.pool(), auth.claims.sub, req).await?),
    ))
}
pub async fn delete_schedule(
    State(s): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    service::delete_schedule(s.db.pool(), auth.claims.sub, id).await?;
    Ok(StatusCode::NO_CONTENT)
}

pub async fn verify_backup(
    State(s): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let result = service::verify_backup(s.db.pool(), auth.claims.sub, id).await?;
    Ok(Json(result))
}

#[derive(serde::Deserialize)]
pub struct RetentionRequest {
    pub keep_count: i64,
}

pub async fn enforce_retention(
    State(s): State<AppState>,
    auth: AuthUser,
    Json(req): Json<RetentionRequest>,
) -> Result<impl IntoResponse, AppError> {
    let deleted = service::enforce_retention(s.db.pool(), auth.claims.sub, req.keep_count).await?;
    Ok(Json(
        serde_json::json!({ "deleted": deleted, "keep_count": req.keep_count }),
    ))
}
