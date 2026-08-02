use crate::models::{ProfileResponse, UpdateProfileRequest};
use pcos_common::error::{AppError, AppResult};
use sqlx::PgPool;
use uuid::Uuid;

/// Fetch the current user's profile with aggregated stats.
pub async fn get_profile(pool: &PgPool, user_id: Uuid) -> AppResult<ProfileResponse> {
    let row = sqlx::query_as::<_, (Uuid, String, String, bool, chrono::DateTime<chrono::Utc>, chrono::DateTime<chrono::Utc>)>(
        "SELECT id, email, display_name, is_active, created_at, updated_at FROM users WHERE id = $1"
    )
    .bind(user_id)
    .fetch_optional(pool)
    .await?
    .ok_or_else(|| AppError::NotFound("User not found".to_string()))?;

    // Count devices
    let device_count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM devices WHERE user_id = $1")
        .bind(user_id)
        .fetch_one(pool)
        .await
        .unwrap_or((0,));

    Ok(ProfileResponse {
        id: row.0,
        email: row.1,
        display_name: row.2,
        is_active: row.3,
        created_at: row.4,
        updated_at: row.5,
        storage_used_bytes: 0, // Will be populated when file management is added
        device_count: device_count.0,
    })
}

/// Update the current user's profile.
pub async fn update_profile(
    pool: &PgPool,
    user_id: Uuid,
    req: UpdateProfileRequest,
) -> AppResult<ProfileResponse> {
    if let Some(ref display_name) = req.display_name {
        sqlx::query("UPDATE users SET display_name = $1, updated_at = NOW() WHERE id = $2")
            .bind(display_name)
            .bind(user_id)
            .execute(pool)
            .await?;
    }

    get_profile(pool, user_id).await
}
