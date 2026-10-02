use crate::models::{
    CreatePairingRequest, Device, DeviceListResponse, DeviceResponse, PairingSessionResponse,
    RedeemPairingRequest, RedeemPairingResponse, RegisterDeviceRequest,
};
use chrono::{DateTime, Duration, Utc};
use once_cell::sync::Lazy;
use pcos_common::error::{AppError, AppResult};
use rand::Rng;
use sqlx::PgPool;
use std::collections::HashMap;
use std::sync::Mutex;
use uuid::Uuid;

#[derive(Clone)]
struct PairingSession {
    user_id: Uuid,
    user_email: String,
    pairing_code: String,
    enrollment_token: String,
    expires_at: DateTime<Utc>,
}

static PAIRING_SESSIONS: Lazy<Mutex<HashMap<String, PairingSession>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

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
        "SELECT * FROM devices WHERE user_id = $1 ORDER BY created_at DESC",
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

/// Create a new one-time device pairing/enrollment session.
pub async fn create_pairing_session(
    pool: &PgPool,
    _state: &pcos_common::AppState,
    user_id: Uuid,
    req: CreatePairingRequest,
) -> AppResult<PairingSessionResponse> {
    let user_email: (String,) = sqlx::query_as("SELECT email FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_one(pool)
        .await
        .map_err(|_| AppError::NotFound("User not found".to_string()))?;

    let ttl_secs = req.expires_in_seconds.unwrap_or(300).clamp(60, 3600);
    let expires_at = Utc::now() + Duration::seconds(ttl_secs as i64);

    let mut rng = rand::thread_rng();
    let pairing_code = format!("{:06}", rng.gen_range(0..1_000_000));
    let enrollment_token = Uuid::new_v4().to_string().replace('-', "");

    let payload = serde_json::json!({
        "pcos": true,
        "v": 1,
        "code": pairing_code,
        "token": enrollment_token,
        "user_id": user_id,
        "expires_at": expires_at.to_rfc3339(),
    });

    let session = PairingSession {
        user_id,
        user_email: user_email.0,
        pairing_code: pairing_code.clone(),
        enrollment_token: enrollment_token.clone(),
        expires_at,
    };

    let mut lock = PAIRING_SESSIONS
        .lock()
        .map_err(|e| AppError::Internal(e.to_string()))?;
    let now = Utc::now();
    lock.retain(|_, s| s.expires_at > now);

    lock.insert(pairing_code.clone(), session.clone());
    lock.insert(enrollment_token.clone(), session);

    tracing::info!(user_id = %user_id, "Device pairing session created with 5-minute TTL");

    Ok(PairingSessionResponse {
        pairing_code,
        enrollment_token,
        expires_at,
        qr_payload: payload.to_string(),
    })
}

/// Redeem a pairing code or enrollment token to provision and authenticate a device.
pub async fn redeem_pairing_session(
    pool: &PgPool,
    state: &pcos_common::AppState,
    req: RedeemPairingRequest,
) -> AppResult<RedeemPairingResponse> {
    let key = req
        .enrollment_token
        .as_deref()
        .or(req.pairing_code.as_deref())
        .ok_or_else(|| {
            AppError::Validation("Either enrollment_token or pairing_code is required".to_string())
        })?;

    let session = {
        let mut lock = PAIRING_SESSIONS
            .lock()
            .map_err(|e| AppError::Internal(e.to_string()))?;
        let sess = lock
            .remove(key)
            .ok_or_else(|| AppError::Unauthorized("Invalid or expired pairing code".to_string()))?;
        lock.remove(&sess.pairing_code);
        lock.remove(&sess.enrollment_token);

        if sess.expires_at < Utc::now() {
            return Err(AppError::Unauthorized(
                "Pairing session has expired".to_string(),
            ));
        }
        sess
    };

    let device_id = Uuid::new_v4();
    let os_ver = req.os_version.unwrap_or_default();
    let agent_ver = req.agent_version.unwrap_or_default();

    let device = sqlx::query_as::<_, Device>(
        r#"
        INSERT INTO devices (id, user_id, name, device_type, os, os_version, agent_version, is_online, last_seen_at, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, true, NOW(), NOW(), NOW())
        RETURNING *
        "#,
    )
    .bind(device_id)
    .bind(session.user_id)
    .bind(&req.device_name)
    .bind(&req.device_type)
    .bind(&req.os)
    .bind(&os_ver)
    .bind(&agent_ver)
    .fetch_one(pool)
    .await?;

    let tokens = pcos_common::auth::jwt::generate_token_pair(
        session.user_id,
        &session.user_email,
        &state.config.auth,
    )?;

    // Store refresh token
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(tokens.refresh_token.as_bytes());
    let token_hash = hex::encode(hasher.finalize());
    let exp = Utc::now() + Duration::seconds(state.config.auth.refresh_token_expiry_secs);
    sqlx::query(
        "INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at, revoked, created_at) VALUES ($1, $2, $3, $4, false, NOW())",
    )
    .bind(Uuid::new_v4())
    .bind(session.user_id)
    .bind(token_hash)
    .bind(exp)
    .execute(pool)
    .await?;

    tracing::info!(device_id = %device.id, user_id = %session.user_id, "Device enrolled via pairing");

    Ok(RedeemPairingResponse {
        device: device.into(),
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
    })
}
