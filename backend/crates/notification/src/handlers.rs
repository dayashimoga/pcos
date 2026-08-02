use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Deserialize)]
pub struct CreateNotificationRequest {
    pub title: String,
    pub body: String,
    pub user_id: Option<Uuid>,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct NotificationRow {
    pub id: Uuid,
    pub title: String,
    pub body: String,
    pub is_read: bool,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// POST /api/v1/notifications
pub async fn create_notification(
    State(s): State<AppState>, auth: AuthUser, Json(req): Json<CreateNotificationRequest>,
) -> Result<impl IntoResponse, AppError> {
    let target_user_id = req.user_id.unwrap_or(auth.claims.sub);

    let row = sqlx::query_as::<_, NotificationRow>(
        "INSERT INTO notifications (user_id, title, body) VALUES ($1, $2, $3) RETURNING id, title, body, is_read, created_at"
    )
    .bind(target_user_id).bind(&req.title).bind(&req.body)
    .fetch_one(s.db.pool()).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok((StatusCode::CREATED, Json(row)))
}

/// GET /api/v1/notifications
pub async fn list_notifications(
    State(s): State<AppState>, auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let rows = sqlx::query_as::<_, NotificationRow>(
        "SELECT id, title, body, is_read, created_at FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50"
    ).bind(auth.claims.sub).fetch_all(s.db.pool()).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    let total = rows.len();
    Ok(Json(serde_json::json!({ "notifications": rows, "total": total })))
}

/// PUT /api/v1/notifications/:id/read
pub async fn mark_read(
    State(s): State<AppState>, auth: AuthUser, Path(id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    sqlx::query("UPDATE notifications SET is_read = true WHERE id = $1 AND user_id = $2")
        .bind(id).bind(auth.claims.sub).execute(s.db.pool()).await
        .map_err(|e| AppError::Internal(e.to_string()))?;
    Ok(Json(serde_json::json!({ "message": "Marked as read" })))
}

/// POST /api/v1/notifications/read-all
pub async fn mark_all_read(
    State(s): State<AppState>, auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let result = sqlx::query("UPDATE notifications SET is_read = true WHERE user_id = $1 AND is_read = false")
        .bind(auth.claims.sub).execute(s.db.pool()).await
        .map_err(|e| AppError::Internal(e.to_string()))?;
    Ok(Json(serde_json::json!({ "message": "All marked as read", "count": result.rows_affected() })))
}

/// GET /api/v1/notifications/unread-count
pub async fn unread_count(
    State(s): State<AppState>, auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let row: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_read = false")
        .bind(auth.claims.sub).fetch_one(s.db.pool()).await
        .map_err(|e| AppError::Internal(e.to_string()))?;
    Ok(Json(serde_json::json!({ "unread_count": row.0 })))
}

/// System helper — create notification programmatically from other services
pub async fn create_system_notification(pool: &sqlx::PgPool, user_id: Uuid, title: &str, body: &str) -> Result<(), AppError> {
    sqlx::query("INSERT INTO notifications (user_id, title, body) VALUES ($1, $2, $3)")
        .bind(user_id).bind(title).bind(body)
        .execute(pool).await
        .map_err(|e| AppError::Internal(e.to_string()))?;
    Ok(())
}
