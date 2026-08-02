use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use serde::Deserialize;
use uuid::Uuid;

#[derive(Debug, Deserialize)]
pub struct CreateNotificationRequest {
    pub title: String,
    pub body: String,
    pub user_id: Option<Uuid>, // If None, send to self
}

/// POST /api/v1/notifications — create a notification
pub async fn create_notification(
    State(s): State<AppState>, auth: AuthUser, Json(req): Json<CreateNotificationRequest>,
) -> Result<impl IntoResponse, AppError> {
    let target_user_id = req.user_id.unwrap_or(auth.claims.sub);

    sqlx::query("INSERT INTO notifications (user_id, title, body) VALUES ($1, $2, $3)")
        .bind(target_user_id).bind(&req.title).bind(&req.body)
        .execute(s.db.pool()).await.map_err(|e| AppError::Internal(e.to_string()))?;

    Ok((StatusCode::CREATED, Json(serde_json::json!({ "message": "Notification created" }))))
}

pub async fn list_notifications(State(s): State<AppState>, auth: AuthUser) -> Result<impl IntoResponse, AppError> {
    let rows: Vec<(Uuid, String, String, bool, chrono::DateTime<chrono::Utc>)> = sqlx::query_as(
        "SELECT id, title, body, is_read, created_at FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50"
    ).bind(auth.claims.sub).fetch_all(s.db.pool()).await.map_err(|e| AppError::Internal(e.to_string()))?;

    let notifs: Vec<serde_json::Value> = rows.into_iter().map(|(id, title, body, read, ts)| {
        serde_json::json!({ "id": id, "title": title, "body": body, "is_read": read, "created_at": ts })
    }).collect();
    Ok(Json(serde_json::json!({ "notifications": notifs, "total": notifs.len() })))
}

pub async fn mark_read(State(s): State<AppState>, auth: AuthUser, axum::extract::Path(id): axum::extract::Path<Uuid>) -> Result<impl IntoResponse, AppError> {
    sqlx::query("UPDATE notifications SET is_read = true WHERE id = $1 AND user_id = $2")
        .bind(id).bind(auth.claims.sub).execute(s.db.pool()).await.map_err(|e| AppError::Internal(e.to_string()))?;
    Ok(Json(serde_json::json!({ "message": "Marked as read" })))
}

pub async fn mark_all_read(State(s): State<AppState>, auth: AuthUser) -> Result<impl IntoResponse, AppError> {
    let result = sqlx::query("UPDATE notifications SET is_read = true WHERE user_id = $1 AND is_read = false")
        .bind(auth.claims.sub).execute(s.db.pool()).await.map_err(|e| AppError::Internal(e.to_string()))?;
    Ok(Json(serde_json::json!({ "message": "All marked as read", "count": result.rows_affected() })))
}

pub async fn unread_count(State(s): State<AppState>, auth: AuthUser) -> Result<impl IntoResponse, AppError> {
    let (count,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_read = false")
        .bind(auth.claims.sub).fetch_one(s.db.pool()).await.unwrap_or((0,));
    Ok(Json(serde_json::json!({ "unread_count": count })))
}

/// Helper: create notification programmatically (used by other services)
pub async fn create_system_notification(pool: &sqlx::PgPool, user_id: Uuid, title: &str, body: &str) -> Result<(), AppError> {
    sqlx::query("INSERT INTO notifications (user_id, title, body) VALUES ($1, $2, $3)")
        .bind(user_id).bind(title).bind(body)
        .execute(pool).await.map_err(|e| AppError::Internal(e.to_string()))?;
    Ok(())
}
