use crate::models::{Device, DeviceListResponse, DeviceResponse, RegisterDeviceRequest};
use pcos_common::error::{AppError, AppResult};
use sqlx::PgPool;
use uuid::Uuid;

/// Register a new device for the user.
pub async fn register_device(
    pool: &PgPool,
    user_id: Uuid,
    req: RegisterDeviceRequest,
) -> AppResult<DeviceResponse> {
    let device = sqlx::query_as::<_, Device>(
        r#"
        INSERT INTO devices (id, user_id, name, device_type, os, os_version, agent_version, is_online, last_seen_at, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, false, NULL, NOW(), NOW())
        RETURNING *
        "#,
    )
    .bind(Uuid::new_v4())
    .bind(user_id)
    .bind(&req.name)
    .bind(&req.device_type)
    .bind(&req.os)
    .bind(&req.os_version)
    .bind(&req.agent_version)
    .fetch_one(pool)
    .await?;

    tracing::info!(device_id = %device.id, user_id = %user_id, "Device registered");

    Ok(device.into())
}

/// List all devices for a user.
pub async fn list_devices(pool: &PgPool, user_id: Uuid) -> AppResult<DeviceListResponse> {
    let devices = sqlx::query_as::<_, Device>(
        "SELECT * FROM devices WHERE user_id = $1 ORDER BY created_at DESC"
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    let total = devices.len() as i64;
    let device_responses: Vec<DeviceResponse> = devices.into_iter().map(Into::into).collect();

    Ok(DeviceListResponse {
        devices: device_responses,
        total,
    })
}

/// Remove a device (must belong to the user).
pub async fn remove_device(pool: &PgPool, user_id: Uuid, device_id: Uuid) -> AppResult<()> {
    let result = sqlx::query("DELETE FROM devices WHERE id = $1 AND user_id = $2")
        .bind(device_id)
        .bind(user_id)
        .execute(pool)
        .await?;

    if result.rows_affected() == 0 {
        return Err(AppError::NotFound("Device not found".to_string()));
    }

    tracing::info!(device_id = %device_id, user_id = %user_id, "Device removed");

    Ok(())
}

/// Update device heartbeat (marks device as online with current timestamp).
pub async fn heartbeat(pool: &PgPool, user_id: Uuid, device_id: Uuid) -> AppResult<()> {
    let result = sqlx::query(
        "UPDATE devices SET is_online = true, last_seen_at = NOW(), updated_at = NOW() WHERE id = $1 AND user_id = $2"
    )
    .bind(device_id)
    .bind(user_id)
    .execute(pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(AppError::NotFound("Device not found".to_string()));
    }

    Ok(())
}
