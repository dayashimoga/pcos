//! PCOS Emergency Account Recovery
//!
//! Generates and verifies BIP-39 12-word mnemonic phrases for break-glass
//! account recovery and password reset without third-party email/SMS dependencies.
//! Conforms to Bitcoin Improvement Proposal 39 (RFC 2898 / BIP-39) with 2048 words
//! and 4-bit SHA-256 checksum verification.

use axum::extract::State;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::auth::password::hash_password;
use pcos_common::error::AppError;
use pcos_common::AppState;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::OnceLock;
use uuid::Uuid;

static BIP39_RAW: &str = include_str!("bip39_english.txt");

fn get_word_list() -> &'static [&'static str] {
    static WORD_LIST: OnceLock<Vec<&'static str>> = OnceLock::new();
    WORD_LIST.get_or_init(|| {
        BIP39_RAW.lines().map(|l| l.trim()).filter(|l| !l.is_empty()).collect()
    })
}

fn get_word_map() -> &'static HashMap<&'static str, usize> {
    static WORD_MAP: OnceLock<HashMap<&'static str, usize>> = OnceLock::new();
    WORD_MAP.get_or_init(|| {
        let words = get_word_list();
        let mut map = HashMap::with_capacity(words.len());
        for (idx, word) in words.iter().enumerate() {
            map.insert(*word, idx);
        }
        map
    })
}

/// Generate a 12-word BIP-39 phrase with 128-bit entropy and 4-bit checksum.
pub fn generate_bip39_phrase() -> String {
    let mut entropy = [0u8; 16];
    rand::thread_rng().fill_bytes(&mut entropy);

    // Compute checksum: SHA256 of 128-bit entropy; first 4 bits is checksum
    let mut hasher = Sha256::new();
    hasher.update(&entropy);
    let hash = hasher.finalize();
    let checksum = (hash[0] >> 4) & 0x0F;

    // Convert 132 bits into 12 11-bit chunks
    let words = get_word_list();
    let mut indices = Vec::with_capacity(12);

    let mut bit_buffer: u32 = 0;
    let mut bit_count: usize = 0;

    for &byte in &entropy {
        bit_buffer = (bit_buffer << 8) | (byte as u32);
        bit_count += 8;
        while bit_count >= 11 {
            let idx = ((bit_buffer >> (bit_count - 11)) & 0x7FF) as usize;
            indices.push(idx);
            bit_count -= 11;
        }
    }

    // Append 4-bit checksum
    bit_buffer = (bit_buffer << 4) | (checksum as u32);
    let idx = (bit_buffer & 0x7FF) as usize;
    indices.push(idx);

    indices.iter().map(|&i| words[i]).collect::<Vec<_>>().join(" ")
}

/// Validate that a 12-word mnemonic phrase conforms to BIP-39 standards,
/// including dictionary validation and 4-bit checksum verification.
pub fn validate_bip39_phrase(phrase: &str) -> Result<(), &'static str> {
    let raw_words: Vec<&str> = phrase.trim().split_whitespace().collect();
    if raw_words.len() != 12 {
        return Err("Mnemonic phrase must consist of exactly 12 words");
    }

    let word_map = get_word_map();
    let mut indices = Vec::with_capacity(12);
    for w in raw_words {
        let lower = w.to_lowercase();
        match word_map.get(lower.as_str()) {
            Some(&idx) => indices.push(idx),
            None => return Err("Unknown word in BIP-39 mnemonic phrase"),
        }
    }

    // Reconstruct 132 bits: 128 bits entropy + 4 bits checksum
    let mut entropy = [0u8; 16];
    let mut bit_buffer: u32 = 0;
    let mut bit_count: usize = 0;
    let mut byte_idx: usize = 0;

    for &idx in indices.iter().take(11) {
        bit_buffer = (bit_buffer << 11) | (idx as u32);
        bit_count += 11;
        while bit_count >= 8 && byte_idx < 16 {
            entropy[byte_idx] = ((bit_buffer >> (bit_count - 8)) & 0xFF) as u8;
            byte_idx += 1;
            bit_count -= 8;
        }
    }

    // 12th word
    let last_idx = indices[11] as u32;
    bit_buffer = (bit_buffer << 11) | last_idx;
    entropy[15] = ((bit_buffer >> 4) & 0xFF) as u8;
    let provided_checksum = (bit_buffer & 0x0F) as u8;

    let mut hasher = Sha256::new();
    hasher.update(&entropy);
    let hash = hasher.finalize();
    let expected_checksum = (hash[0] >> 4) & 0x0F;

    if provided_checksum != expected_checksum {
        return Err("BIP-39 checksum verification failed: invalid or mistyped recovery phrase");
    }

    Ok(())
}

#[derive(Serialize)]
pub struct GenerateRecoveryResponse {
    pub success: bool,
    pub recovery_phrase: String,
    pub recovery_key: String,
    pub message: String,
}

#[derive(Deserialize)]
pub struct VerifyRecoveryRequest {
    pub email: String,
    pub recovery_phrase: Option<String>,
    pub recovery_key: Option<String>,
    pub new_password: String,
}

#[derive(Serialize)]
pub struct VerifyRecoveryResponse {
    pub success: bool,
    pub message: String,
}

pub fn hash_phrase(phrase: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(phrase.trim().to_lowercase().as_bytes());
    hex::encode(hasher.finalize())
}

/// POST /api/v1/auth/recovery/generate
pub async fn generate_recovery_phrase(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<Json<GenerateRecoveryResponse>, AppError> {
    let phrase = generate_bip39_phrase();
    let rec_hash = hash_phrase(&phrase);
    let key_id = format!("rec_{}", Uuid::new_v4());

    sqlx::query(
        "INSERT INTO recovery_keys (id, user_id, recovery_hash, hint, is_used, created_at) VALUES ($1, $2, $3, $4, false, NOW())"
    )
    .bind(&key_id)
    .bind(auth.claims.sub)
    .bind(&rec_hash)
    .bind("Official standard BIP-39 12-word mnemonic phrase")
    .execute(state.db.pool())
    .await?;

    Ok(Json(GenerateRecoveryResponse {
        success: true,
        recovery_phrase: phrase,
        recovery_key: key_id,
        message: "Store this 12-word emergency phrase safely offline. It allows resetting your password if locked out.".to_string(),
    }))
}

/// POST /api/v1/auth/recovery/verify
pub async fn verify_recovery_phrase(
    State(state): State<AppState>,
    Json(req): Json<VerifyRecoveryRequest>,
) -> Result<Json<VerifyRecoveryResponse>, AppError> {
    let email = req.email.trim().to_lowercase();
    pcos_common::auth::validation::validate_password(&req.new_password)?;

    let input_phrase = req
        .recovery_phrase
        .or(req.recovery_key)
        .ok_or_else(|| AppError::Validation("recovery_phrase or recovery_key required".into()))?;

    // If a 12-word phrase is supplied, enforce BIP-39 dictionary and checksum validation
    if input_phrase.split_whitespace().count() == 12 {
        if let Err(err_msg) = validate_bip39_phrase(&input_phrase) {
            return Err(AppError::Validation(err_msg.to_string()));
        }
    }

    let rec_hash = hash_phrase(&input_phrase);

    // Look up user
    let user_row: (Uuid,) = sqlx::query_as("SELECT id FROM users WHERE email = $1")
        .bind(&email)
        .fetch_one(state.db.pool())
        .await
        .map_err(|_| AppError::NotFound("User not found".into()))?;

    let user_id = user_row.0;

    // Check matching unused recovery key
    let key_row: (String,) = sqlx::query_as(
        "SELECT id FROM recovery_keys WHERE user_id = $1 AND recovery_hash = $2 AND is_used = false"
    )
    .bind(user_id)
    .bind(&rec_hash)
    .fetch_one(state.db.pool())
    .await
    .map_err(|_| AppError::Unauthorized("Invalid or already consumed recovery phrase".into()))?;

    // Hash new password
    let new_hash = hash_password(&req.new_password)
        .map_err(|e| AppError::Internal(format!("Password hashing failed: {e}")))?;

    // Update password
    sqlx::query("UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2")
        .bind(&new_hash)
        .bind(user_id)
        .execute(state.db.pool())
        .await?;

    // Mark recovery key as consumed
    sqlx::query("UPDATE recovery_keys SET is_used = true WHERE id = $1")
        .bind(&key_row.0)
        .execute(state.db.pool())
        .await?;

    // Revoke all existing refresh tokens (SEC-05)
    sqlx::query("UPDATE refresh_tokens SET revoked = true WHERE user_id = $1")
        .bind(user_id)
        .execute(state.db.pool())
        .await?;

    Ok(Json(VerifyRecoveryResponse {
        success: true,
        message: "Password reset successfully via emergency recovery key".to_string(),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bip39_wordlist_size_and_bounds() {
        let words = get_word_list();
        assert_eq!(words.len(), 2048);
        assert_eq!(words[0], "abandon");
        assert_eq!(words[2047], "zoo");
    }

    #[test]
    fn test_generate_and_validate_bip39_phrase() {
        for _ in 0..20 {
            let phrase = generate_bip39_phrase();
            let words: Vec<&str> = phrase.split_whitespace().collect();
            assert_eq!(words.len(), 12);
            assert!(validate_bip39_phrase(&phrase).is_ok());
        }
    }

    #[test]
    fn test_bip39_checksum_tamper_detection() {
        let phrase = generate_bip39_phrase();
        let mut words: Vec<&str> = phrase.split_whitespace().collect();
        // Tamper with the last word
        words[11] = if words[11] == "abandon" { "zoo" } else { "abandon" };
        let tampered = words.join(" ");
        let result = validate_bip39_phrase(&tampered);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "BIP-39 checksum verification failed: invalid or mistyped recovery phrase");
    }

    #[test]
    fn test_bip39_rejects_unknown_words() {
        let invalid = "notabipword ability able about above absent absorb abstract absurd abuse access accident";
        let result = validate_bip39_phrase(invalid);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Unknown word in BIP-39 mnemonic phrase");
    }

    #[test]
    fn test_hash_phrase_deterministic() {
        let phrase = "abandon ability able about above absent absorb abstract absurd abuse access accident";
        let h1 = hash_phrase(phrase);
        let h2 = hash_phrase(&phrase.to_uppercase());
        assert_eq!(h1, h2);
        assert_eq!(h1.len(), 64);
    }
}
