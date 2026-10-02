use crate::models::{
    ApprovePairingRequest, CandidateDevice, ClaimPairingRequest, CreatePairingRequest, Device,
    DeviceListResponse, DeviceResponse, PairingSessionResponse, PairingStatusResponse,
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
    id: Uuid,
    user_id: Uuid,
    user_email: String,
    pairing_code: String,
    enrollment_token: String,
    expires_at: DateTime<Utc>,
    status: String, // "pending_redeem", "pending_approval", "approved", "rejected"
    failed_attempts: u32,
    candidate_device: Option<CandidateDevice>,
    redeem_result: Option<RedeemPairingResponse>,
}

struct PairingStore {
    sessions: HashMap<Uuid, PairingSession>,
    code_to_id: HashMap<String, Uuid>,
    token_to_id: HashMap<String, Uuid>,
}

impl PairingStore {
    fn new() -> Self {
        Self {
            sessions: HashMap::new(),
            code_to_id: HashMap::new(),
            token_to_id: HashMap::new(),
        }
    }

    fn cleanup_expired(&mut self) {
        let now = Utc::now();
        let expired_ids: Vec<Uuid> = self
            .sessions
            .iter()
            .filter(|(_, s)| s.expires_at <= now)
            .map(|(id, _)| *id)
            .collect();
        for id in expired_ids {
            self.remove(id);
        }
    }

    fn insert(&mut self, session: PairingSession) {
        let id = session.id;
        self.code_to_id.insert(session.pairing_code.clone(), id);
        self.token_to_id
            .insert(session.enrollment_token.clone(), id);
        self.sessions.insert(id, session);
    }

    fn get_by_key(&self, key: &str) -> Option<&PairingSession> {
        let id = self
            .code_to_id
            .get(key)
            .or_else(|| self.token_to_id.get(key))?;
        self.sessions.get(id)
    }

    fn get_mut_by_key(&mut self, key: &str) -> Option<&mut PairingSession> {
        let id = *self
            .code_to_id
            .get(key)
            .or_else(|| self.token_to_id.get(key))?;
        self.sessions.get_mut(&id)
    }

    fn remove(&mut self, id: Uuid) -> Option<PairingSession> {
        if let Some(sess) = self.sessions.remove(&id) {
            self.code_to_id.remove(&sess.pairing_code);
            self.token_to_id.remove(&sess.enrollment_token);
            Some(sess)
        } else {
            None
        }
    }

    #[allow(dead_code)]
    fn remove_by_key(&mut self, key: &str) -> Option<PairingSession> {
        let id = *self
            .code_to_id
            .get(key)
            .or_else(|| self.token_to_id.get(key))?;
        self.remove(id)
    }
}

static PAIRING_STORE: Lazy<Mutex<PairingStore>> = Lazy::new(|| Mutex::new(PairingStore::new()));

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

    let server_url = std::env::var("PCOS_PUBLIC_URL")
        .or_else(|_| {
            std::env::var("PCOS_LAN_IP")
                .or_else(|_| std::env::var("PCOS_SERVER_IP"))
                .map(|ip| {
                    let trimmed = ip.trim();
                    if trimmed.starts_with("http://") || trimmed.starts_with("https://") {
                        trimmed.trim_end_matches('/').to_string()
                    } else {
                        format!("http://{}", trimmed.trim_end_matches('/'))
                    }
                })
        })
        .unwrap_or_else(|_| "http://localhost".to_string());

    let universal_link = format!(
        "{}/#/pair?code={}&token={}",
        server_url, pairing_code, enrollment_token
    );

    let session = PairingSession {
        id: Uuid::new_v4(),
        user_id,
        user_email: user_email.0,
        pairing_code: pairing_code.clone(),
        enrollment_token: enrollment_token.clone(),
        expires_at,
        status: "pending_redeem".to_string(),
        failed_attempts: 0,
        candidate_device: None,
        redeem_result: None,
    };

    let mut store = PAIRING_STORE
        .lock()
        .map_err(|e| AppError::Internal(e.to_string()))?;
    store.cleanup_expired();
    store.insert(session);

    tracing::info!(user_id = %user_id, "Device pairing session created with 5-minute TTL");

    Ok(PairingSessionResponse {
        pairing_code,
        enrollment_token,
        expires_at,
        qr_payload: universal_link,
    })
}

/// Mobile device claims a pairing code and submits candidate device metadata for user approval.
pub async fn claim_pairing_session(req: ClaimPairingRequest) -> AppResult<PairingStatusResponse> {
    let key = req
        .enrollment_token
        .as_deref()
        .or(req.pairing_code.as_deref())
        .ok_or_else(|| {
            AppError::Validation("Either enrollment_token or pairing_code is required".to_string())
        })?;

    let mut store = PAIRING_STORE
        .lock()
        .map_err(|e| AppError::Internal(e.to_string()))?;

    let sess = store
        .get_mut_by_key(key)
        .ok_or_else(|| AppError::Unauthorized("Invalid or expired pairing code".to_string()))?;

    if sess.expires_at < Utc::now() {
        return Err(AppError::Unauthorized(
            "Pairing session has expired".to_string(),
        ));
    }

    if sess.failed_attempts >= 5 {
        let id = sess.id;
        store.remove(id);
        return Err(AppError::Unauthorized(
            "Too many failed attempts. Pairing session invalidated.".to_string(),
        ));
    }

    let candidate = CandidateDevice {
        device_name: req.device_name,
        device_type: req.device_type,
        os: req.os,
        os_version: req.os_version.unwrap_or_default(),
        agent_version: req.agent_version.unwrap_or_default(),
        client_fingerprint: req.client_fingerprint,
        requested_at: Utc::now(),
    };

    sess.candidate_device = Some(candidate.clone());
    sess.status = "pending_approval".to_string();
    let pairing_code = sess.pairing_code.clone();
    let enrollment_token = sess.enrollment_token.clone();
    let expires_at = sess.expires_at;

    tracing::info!(device = %candidate.device_name, "Pairing claimed by device — waiting for approval");

    Ok(PairingStatusResponse {
        pairing_code,
        enrollment_token,
        status: "pending_approval".to_string(),
        expires_at,
        candidate_device: Some(candidate),
        redeem_result: None,
    })
}

/// Web client approves or rejects the candidate device connection.
pub async fn approve_pairing_session(
    pool: &PgPool,
    state: &pcos_common::AppState,
    user_id: Uuid,
    req: ApprovePairingRequest,
) -> AppResult<PairingStatusResponse> {
    let key = req
        .enrollment_token
        .as_deref()
        .or(req.pairing_code.as_deref())
        .ok_or_else(|| {
            AppError::Validation("Either enrollment_token or pairing_code is required".to_string())
        })?;

    let (sess_user_id, sess_user_email, candidate, expires_at, pairing_code, enrollment_token) = {
        let mut store = PAIRING_STORE
            .lock()
            .map_err(|e| AppError::Internal(e.to_string()))?;

        let sess = store
            .get_mut_by_key(key)
            .ok_or_else(|| AppError::Unauthorized("Invalid or expired pairing code".to_string()))?;

        if sess.user_id != user_id {
            return Err(AppError::Unauthorized(
                "You do not own this pairing session".to_string(),
            ));
        }

        if sess.expires_at < Utc::now() {
            return Err(AppError::Unauthorized(
                "Pairing session has expired".to_string(),
            ));
        }

        if !req.approved {
            sess.status = "rejected".to_string();
            let code = sess.pairing_code.clone();
            let tok = sess.enrollment_token.clone();
            let cand = sess.candidate_device.clone();
            let exp = sess.expires_at;
            tracing::warn!(user_id = %user_id, "Device pairing rejected by user");
            return Ok(PairingStatusResponse {
                pairing_code: code,
                enrollment_token: tok,
                status: "rejected".to_string(),
                expires_at: exp,
                candidate_device: cand,
                redeem_result: None,
            });
        }

        let cand = sess.candidate_device.clone().ok_or_else(|| {
            AppError::Validation(
                "No candidate device has claimed this pairing code yet".to_string(),
            )
        })?;

        (
            sess.user_id,
            sess.user_email.clone(),
            cand,
            sess.expires_at,
            sess.pairing_code.clone(),
            sess.enrollment_token.clone(),
        )
    };

    // Database device creation
    let device_id = Uuid::new_v4();
    let device = sqlx::query_as::<_, Device>(
        r#"
        INSERT INTO devices (id, user_id, name, device_type, os, os_version, agent_version, is_online, last_seen_at, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, true, NOW(), NOW(), NOW())
        RETURNING *
        "#,
    )
    .bind(device_id)
    .bind(sess_user_id)
    .bind(&candidate.device_name)
    .bind(&candidate.device_type)
    .bind(&candidate.os)
    .bind(&candidate.os_version)
    .bind(&candidate.agent_version)
    .fetch_one(pool)
    .await?;

    let tokens = pcos_common::auth::jwt::generate_token_pair(
        sess_user_id,
        &sess_user_email,
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
    .bind(sess_user_id)
    .bind(token_hash)
    .bind(exp)
    .execute(pool)
    .await?;

    let redeem_result = RedeemPairingResponse {
        device: device.into(),
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
    };

    // Store redeem_result in session
    {
        let mut store = PAIRING_STORE
            .lock()
            .map_err(|e| AppError::Internal(e.to_string()))?;
        if let Some(sess) = store.get_mut_by_key(key) {
            sess.status = "approved".to_string();
            sess.redeem_result = Some(redeem_result.clone());
        }
    }

    tracing::info!(user_id = %sess_user_id, device = %candidate.device_name, "Pairing approved and device provisioned");

    Ok(PairingStatusResponse {
        pairing_code,
        enrollment_token,
        status: "approved".to_string(),
        expires_at,
        candidate_device: Some(candidate),
        redeem_result: Some(redeem_result),
    })
}

/// Check the status of a pairing session.
pub async fn get_pairing_status(key: &str) -> AppResult<PairingStatusResponse> {
    let store = PAIRING_STORE
        .lock()
        .map_err(|e| AppError::Internal(e.to_string()))?;

    let sess = store
        .get_by_key(key)
        .ok_or_else(|| AppError::Unauthorized("Invalid or expired pairing code".to_string()))?;

    let now = Utc::now();
    let status = if sess.expires_at < now {
        "expired".to_string()
    } else {
        sess.status.clone()
    };

    Ok(PairingStatusResponse {
        pairing_code: sess.pairing_code.clone(),
        enrollment_token: sess.enrollment_token.clone(),
        status,
        expires_at: sess.expires_at,
        candidate_device: sess.candidate_device.clone(),
        redeem_result: sess.redeem_result.clone(),
    })
}

/// Redeem a pairing code or enrollment token to provision and authenticate a device.
/// Supports both pre-approved two-step pairing and direct single-step enrollment.
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
        let mut store = PAIRING_STORE
            .lock()
            .map_err(|e| AppError::Internal(e.to_string()))?;
        let sess = store
            .get_by_key(key)
            .ok_or_else(|| AppError::Unauthorized("Invalid or expired pairing code".to_string()))?;

        if sess.expires_at < Utc::now() {
            return Err(AppError::Unauthorized(
                "Pairing session has expired".to_string(),
            ));
        }

        if sess.status == "rejected" {
            return Err(AppError::Unauthorized(
                "Pairing request was rejected by device owner".to_string(),
            ));
        }

        if let Some(result) = sess.redeem_result.clone() {
            // Pre-approved! Consume session immediately (single-use)
            let id = sess.id;
            store.remove(id);
            return Ok(result);
        }

        sess.clone()
    };

    // If candidate device was already claimed but not approved yet:
    if session.status == "pending_approval" {
        return Err(AppError::Unauthorized(
            "Waiting for device approval on your PCOS Web/Desktop screen".to_string(),
        ));
    }

    // Direct single-step enrollment (provisions device directly)
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

    // Invalidate pairing session immediately (single use)
    {
        let mut store = PAIRING_STORE
            .lock()
            .map_err(|e| AppError::Internal(e.to_string()))?;
        store.remove(session.id);
    }

    tracing::info!(device_id = %device.id, user_id = %session.user_id, "Device enrolled via pairing");

    Ok(RedeemPairingResponse {
        device: device.into(),
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pairing_store_lifecycle_and_replay_prevention() {
        let mut store = PairingStore::new();
        let session_id = Uuid::new_v4();
        let user_id = Uuid::new_v4();
        let code = "123456".to_string();
        let token = "tok_abcdef123456".to_string();

        let session = PairingSession {
            id: session_id,
            user_id,
            user_email: "alice@pcos.local".to_string(),
            pairing_code: code.clone(),
            enrollment_token: token.clone(),
            expires_at: Utc::now() + Duration::seconds(300),
            status: "pending_redeem".to_string(),
            failed_attempts: 0,
            candidate_device: None,
            redeem_result: None,
        };

        // 1. Insert and verify dual-key indexing
        store.insert(session);
        assert!(store.get_by_key(&code).is_some());
        assert!(store.get_by_key(&token).is_some());

        // 2. Claim device
        {
            let sess = store.get_mut_by_key(&code).unwrap();
            sess.status = "pending_approval".to_string();
            sess.candidate_device = Some(CandidateDevice {
                device_name: "Pixel 9".into(),
                device_type: "phone".into(),
                os: "android".into(),
                os_version: "15".into(),
                agent_version: "0.1.0".into(),
                client_fingerprint: Some("fp_xyz".into()),
                requested_at: Utc::now(),
            });
        }

        // Verify status was updated through token index
        let retrieved = store.get_by_key(&token).unwrap();
        assert_eq!(retrieved.status, "pending_approval");
        assert_eq!(
            retrieved.candidate_device.as_ref().unwrap().device_name,
            "Pixel 9"
        );

        // 3. Remove on redemption (single use / replay prevention)
        let removed = store.remove(session_id);
        assert!(removed.is_some());

        // Replay attempt must fail
        assert!(store.get_by_key(&code).is_none());
        assert!(store.get_by_key(&token).is_none());
    }

    #[test]
    fn test_pairing_store_expired_cleanup() {
        let mut store = PairingStore::new();
        let id = Uuid::new_v4();
        let session = PairingSession {
            id,
            user_id: Uuid::new_v4(),
            user_email: "bob@pcos.local".to_string(),
            pairing_code: "999999".to_string(),
            enrollment_token: "tok_expired".to_string(),
            expires_at: Utc::now() - Duration::seconds(10), // already expired
            status: "pending_redeem".to_string(),
            failed_attempts: 0,
            candidate_device: None,
            redeem_result: None,
        };

        store.insert(session);
        assert!(store.get_by_key("999999").is_some());

        store.cleanup_expired();
        assert!(store.get_by_key("999999").is_none());
    }
}
