use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use serde::{Deserialize, Serialize};
use rand::Rng;

/// Generate a random Base32 TOTP secret (160-bit / 20 bytes)
fn generate_totp_secret() -> String {
    let mut rng = rand::thread_rng();
    let bytes: Vec<u8> = (0..20).map(|_| rng.gen::<u8>()).collect();
    base32_encode(&bytes)
}

fn base32_encode(data: &[u8]) -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    let mut result = String::new();
    let mut buffer: u64 = 0;
    let mut bits = 0;
    for &byte in data {
        buffer = (buffer << 8) | byte as u64;
        bits += 8;
        while bits >= 5 {
            bits -= 5;
            let idx = ((buffer >> bits) & 0x1f) as usize;
            result.push(ALPHABET[idx] as char);
        }
    }
    if bits > 0 {
        let idx = ((buffer << (5 - bits)) & 0x1f) as usize;
        result.push(ALPHABET[idx] as char);
    }
    result
}

/// Compute TOTP value for a given secret at a given time step.
/// Uses SHA-1, 6-digit codes, 30-second time step (RFC 6238).
fn compute_totp(secret_base32: &str, time_step: u64) -> Option<String> {
    let key = base32_decode(secret_base32)?;
    let msg = time_step.to_be_bytes();

    // HMAC-SHA1 (minimal implementation for TOTP)
    let hash = hmac_sha1(&key, &msg);
    let offset = (hash[19] & 0x0f) as usize;
    let code = ((hash[offset] as u32 & 0x7f) << 24)
        | ((hash[offset + 1] as u32) << 16)
        | ((hash[offset + 2] as u32) << 8)
        | (hash[offset + 3] as u32);
    Some(format!("{:06}", code % 1_000_000))
}

fn base32_decode(s: &str) -> Option<Vec<u8>> {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    let mut result = Vec::new();
    let mut buffer: u64 = 0;
    let mut bits = 0;
    for c in s.chars() {
        let val = ALPHABET.iter().position(|&b| b == c.to_ascii_uppercase() as u8)? as u64;
        buffer = (buffer << 5) | val;
        bits += 5;
        if bits >= 8 {
            bits -= 8;
            result.push((buffer >> bits) as u8);
        }
    }
    Some(result)
}

fn hmac_sha1(key: &[u8], msg: &[u8]) -> [u8; 20] {
    use sha1_smol::Sha1;

    let block_size = 64;
    let mut k = vec![0u8; block_size];
    if key.len() > block_size {
        let mut hasher = Sha1::new();
        hasher.update(key);
        k[..20].copy_from_slice(&hasher.digest().bytes());
    } else {
        k[..key.len()].copy_from_slice(key);
    }

    let ipad: Vec<u8> = k.iter().map(|b| b ^ 0x36).collect();
    let opad: Vec<u8> = k.iter().map(|b| b ^ 0x5c).collect();

    let mut inner = Sha1::new();
    inner.update(&ipad);
    inner.update(msg);
    let inner_hash = inner.digest().bytes();

    let mut outer = Sha1::new();
    outer.update(&opad);
    outer.update(&inner_hash);
    outer.digest().bytes()
}

fn current_time_step() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() / 30
}

/// Verify TOTP code — checks current step ±1 for clock skew tolerance
fn verify_totp(secret: &str, code: &str) -> bool {
    let step = current_time_step();
    for offset in [0i64, -1, 1] {
        let s = (step as i64 + offset) as u64;
        if let Some(expected) = compute_totp(secret, s) {
            if expected == code { return true; }
        }
    }
    false
}

#[derive(Debug, Deserialize)]
pub struct VerifyTotpRequest {
    pub code: String,
}

/// POST /api/v1/auth/mfa/setup — generate TOTP secret and provisioning URI
pub async fn setup_totp(
    State(state): State<AppState>, auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let pool = state.db.pool();

    // Check if already enabled
    let enabled: (bool,) = sqlx::query_as("SELECT totp_enabled FROM users WHERE id = $1")
        .bind(auth.claims.sub).fetch_one(pool).await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    if enabled.0 {
        return Err(AppError::Conflict("MFA is already enabled".to_string()));
    }

    let secret = generate_totp_secret();

    // Store secret (not yet enabled — needs verification)
    sqlx::query("UPDATE users SET totp_secret = $1 WHERE id = $2")
        .bind(&secret).bind(auth.claims.sub).execute(pool).await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    // Get user email for provisioning URI
    let (email,): (String,) = sqlx::query_as("SELECT email FROM users WHERE id = $1")
        .bind(auth.claims.sub).fetch_one(pool).await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    let uri = format!(
        "otpauth://totp/PCOS:{}?secret={}&issuer=PCOS&algorithm=SHA1&digits=6&period=30",
        email, secret
    );

    Ok((StatusCode::OK, Json(serde_json::json!({
        "secret": secret,
        "provisioning_uri": uri,
        "message": "Scan the QR code with your authenticator app, then verify with POST /api/v1/auth/mfa/verify",
    }))))
}

/// POST /api/v1/auth/mfa/verify — verify TOTP code and enable MFA
pub async fn verify_totp_setup(
    State(state): State<AppState>, auth: AuthUser, Json(req): Json<VerifyTotpRequest>,
) -> Result<impl IntoResponse, AppError> {
    let pool = state.db.pool();

    let (secret,): (Option<String>,) = sqlx::query_as("SELECT totp_secret FROM users WHERE id = $1")
        .bind(auth.claims.sub).fetch_one(pool).await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    let secret = secret.ok_or_else(|| AppError::Validation("TOTP not set up. Call /mfa/setup first".to_string()))?;

    if !verify_totp(&secret, &req.code) {
        return Err(AppError::Unauthorized("Invalid TOTP code".to_string()));
    }

    // Enable MFA
    sqlx::query("UPDATE users SET totp_enabled = true, totp_verified_at = NOW() WHERE id = $1")
        .bind(auth.claims.sub).execute(pool).await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(Json(serde_json::json!({ "message": "MFA enabled successfully" })))
}

/// POST /api/v1/auth/mfa/disable — disable MFA (requires valid TOTP code)
pub async fn disable_totp(
    State(state): State<AppState>, auth: AuthUser, Json(req): Json<VerifyTotpRequest>,
) -> Result<impl IntoResponse, AppError> {
    let pool = state.db.pool();

    let (secret, enabled): (Option<String>, bool) = sqlx::query_as(
        "SELECT totp_secret, totp_enabled FROM users WHERE id = $1"
    ).bind(auth.claims.sub).fetch_one(pool).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    if !enabled {
        return Err(AppError::Validation("MFA is not enabled".to_string()));
    }

    let secret = secret.ok_or_else(|| AppError::Internal("No TOTP secret".to_string()))?;

    if !verify_totp(&secret, &req.code) {
        return Err(AppError::Unauthorized("Invalid TOTP code".to_string()));
    }

    sqlx::query("UPDATE users SET totp_enabled = false, totp_secret = NULL, totp_verified_at = NULL WHERE id = $1")
        .bind(auth.claims.sub).execute(pool).await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(Json(serde_json::json!({ "message": "MFA disabled" })))
}

/// GET /api/v1/auth/mfa/status
pub async fn mfa_status(
    State(state): State<AppState>, auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let (enabled, verified_at): (bool, Option<chrono::DateTime<chrono::Utc>>) = sqlx::query_as(
        "SELECT totp_enabled, totp_verified_at FROM users WHERE id = $1"
    ).bind(auth.claims.sub).fetch_one(state.db.pool()).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(Json(serde_json::json!({
        "mfa_enabled": enabled,
        "verified_at": verified_at,
    })))
}
