use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use serde::Deserialize;
use uuid::Uuid;

/// Check if the authenticated user has admin role.
pub async fn require_admin(state: &AppState, user_id: Uuid) -> Result<(), AppError> {
    let (role,): (String,) = sqlx::query_as("SELECT role FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_one(state.db.pool())
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    if role != "admin" {
        return Err(AppError::Forbidden("Admin access required".to_string()));
    }
    Ok(())
}

#[derive(Debug, Deserialize)]
pub struct UpdateRoleRequest {
    pub user_id: Uuid,
    pub role: String,
}

/// GET /api/v1/admin/users — list all users (admin only)
pub async fn list_users(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    require_admin(&state, auth.claims.sub).await?;

    #[derive(sqlx::FromRow, serde::Serialize)]
    struct UserSummary {
        id: Uuid,
        email: String,
        display_name: String,
        role: String,
        totp_enabled: bool,
        storage_quota_bytes: i64,
        created_at: chrono::DateTime<chrono::Utc>,
    }

    let users = sqlx::query_as::<_, UserSummary>(
        "SELECT id, email, display_name, role, totp_enabled, storage_quota_bytes, created_at FROM users ORDER BY created_at DESC"
    )
    .fetch_all(state.db.pool())
    .await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(Json(
        serde_json::json!({ "users": users, "total": users.len() }),
    ))
}

/// PUT /api/v1/admin/users/role — update user role (admin only)
pub async fn update_role(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<UpdateRoleRequest>,
) -> Result<impl IntoResponse, AppError> {
    require_admin(&state, auth.claims.sub).await?;

    // Validate role
    match req.role.as_str() {
        "admin" | "user" | "viewer" => {}
        _ => {
            return Err(AppError::Validation(
                "Invalid role. Must be: admin, user, viewer".to_string(),
            ))
        }
    }

    // Prevent removing your own admin
    if req.user_id == auth.claims.sub && req.role != "admin" {
        return Err(AppError::Validation(
            "Cannot remove your own admin role".to_string(),
        ));
    }

    sqlx::query("UPDATE users SET role = $1 WHERE id = $2")
        .bind(&req.role)
        .bind(req.user_id)
        .execute(state.db.pool())
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(Json(
        serde_json::json!({ "message": "Role updated", "user_id": req.user_id, "role": req.role }),
    ))
}

#[derive(Debug, Deserialize)]
pub struct UpdateQuotaRequest {
    pub user_id: Uuid,
    pub storage_quota_bytes: i64,
}

/// PUT /api/v1/admin/users/quota — update storage quota (admin only)
pub async fn update_quota(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<UpdateQuotaRequest>,
) -> Result<impl IntoResponse, AppError> {
    require_admin(&state, auth.claims.sub).await?;

    sqlx::query("UPDATE users SET storage_quota_bytes = $1 WHERE id = $2")
        .bind(req.storage_quota_bytes)
        .bind(req.user_id)
        .execute(state.db.pool())
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(Json(
        serde_json::json!({ "message": "Quota updated", "user_id": req.user_id, "quota_bytes": req.storage_quota_bytes }),
    ))
}

/// GET /api/v1/admin/system — system stats (admin only)
pub async fn system_stats(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    require_admin(&state, auth.claims.sub).await?;
    let pool = state.db.pool();

    let (total_users,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM users")
        .fetch_one(pool)
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;
    let (total_files,): (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM file_entries WHERE entry_type = 'file'")
            .fetch_one(pool)
            .await
            .map_err(|e| AppError::Internal(e.to_string()))?;
    let (total_storage,): (i64,) = sqlx::query_as(
        "SELECT COALESCE(SUM(size_bytes), 0) FROM file_entries WHERE entry_type = 'file' AND is_trashed = false",
    )
    .fetch_one(pool)
    .await
    .map_err(|e| AppError::Internal(e.to_string()))?;
    let (total_shares,): (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM share_links WHERE is_active = true")
            .fetch_one(pool)
            .await
            .map_err(|e| AppError::Internal(e.to_string()))?;
    let (total_devices,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM devices")
        .fetch_one(pool)
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(Json(serde_json::json!({
        "total_users": total_users,
        "total_files": total_files,
        "total_storage_bytes": total_storage,
        "total_active_shares": total_shares,
        "total_devices": total_devices,
        "version": env!("CARGO_PKG_VERSION"),
    })))
}
