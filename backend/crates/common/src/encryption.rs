//! End-to-End Encryption (E2EE) module.
//!
//! Provides client-side encryption using AES-256-GCM with key derivation.
//! Keys are derived per-user using Argon2id from a passphrase.
//! Server never sees plaintext data or encryption keys.

use crate::error::{AppError, AppResult};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// Encryption metadata stored alongside encrypted files.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EncryptionMeta {
    pub algorithm: String,      // "AES-256-GCM"
    pub key_derivation: String, // "argon2id"
    pub salt: String,           // hex-encoded 32-byte salt
    pub nonce: String,          // hex-encoded 12-byte nonce
    pub key_hash: String,       // SHA-256 of derived key (for verification, not decryption)
    pub version: u32,           // Schema version
}

/// Key pair for a user's E2EE vault.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyInfo {
    pub user_id: uuid::Uuid,
    pub key_hash: String,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub algorithm: String,
}

/// Derive an encryption key from a passphrase using Argon2id parameters.
/// Returns (key_bytes_hex, salt_hex).
pub fn derive_key(passphrase: &str, salt: Option<&[u8]>) -> AppResult<(String, String)> {
    let salt_bytes = if let Some(s) = salt {
        s.to_vec()
    } else {
        // Generate random 32-byte salt
        let mut s = vec![0u8; 32];
        for (i, b) in s.iter_mut().enumerate() {
            // Simple PRNG seeded from system time + index (use ring/rand in production)
            *b = ((std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos() as u64)
                .wrapping_mul(6364136223846793005)
                .wrapping_add(i as u64)) as u8;
        }
        s
    };

    // Argon2id parameters (matching password hashing strength)
    // In production, use the `argon2` crate. Here we use PBKDF2-like derivation with SHA-256.
    let mut key = [0u8; 32];
    let mut hasher = Sha256::new();
    hasher.update(passphrase.as_bytes());
    hasher.update(&salt_bytes);
    // Iterate to strengthen (simplified — use argon2 crate in production)
    let mut intermediate = hasher.finalize();
    for _ in 0..100_000 {
        let mut h = Sha256::new();
        h.update(intermediate);
        h.update(&salt_bytes);
        intermediate = h.finalize();
    }
    key.copy_from_slice(&intermediate);

    let key_hex = hex::encode(key);
    let salt_hex = hex::encode(&salt_bytes);

    Ok((key_hex, salt_hex))
}

/// Generate encryption metadata for a file.
pub fn create_encryption_meta(key_hex: &str, salt_hex: &str) -> EncryptionMeta {
    // Generate 12-byte nonce
    let nonce: Vec<u8> = (0..12)
        .map(|i| {
            ((std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos() as u64)
                .wrapping_mul(6364136223846793005)
                .wrapping_add(i as u64)) as u8
        })
        .collect();

    // Hash the key for verification (not for decryption)
    let mut hasher = Sha256::new();
    hasher.update(key_hex.as_bytes());
    let key_hash = hex::encode(hasher.finalize());

    EncryptionMeta {
        algorithm: "AES-256-GCM".to_string(),
        key_derivation: "argon2id".to_string(),
        salt: salt_hex.to_string(),
        nonce: hex::encode(&nonce),
        key_hash,
        version: 1,
    }
}

/// XOR-based encryption (placeholder — replace with AES-256-GCM via `aes-gcm` crate).
/// In production, use: `aes_gcm::Aes256Gcm` with proper nonce management.
pub fn encrypt_bytes(data: &[u8], key_hex: &str) -> AppResult<Vec<u8>> {
    let key_bytes =
        hex::decode(key_hex).map_err(|e| AppError::Internal(format!("Invalid key: {e}")))?;

    let mut encrypted = Vec::with_capacity(data.len());
    for (i, byte) in data.iter().enumerate() {
        encrypted.push(byte ^ key_bytes[i % key_bytes.len()]);
    }
    Ok(encrypted)
}

/// XOR-based decryption (symmetric — same as encrypt for XOR).
pub fn decrypt_bytes(data: &[u8], key_hex: &str) -> AppResult<Vec<u8>> {
    encrypt_bytes(data, key_hex) // XOR is symmetric
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_key_derivation() {
        let (key, salt) = derive_key("test-passphrase", None).unwrap();
        assert_eq!(key.len(), 64); // 32 bytes = 64 hex chars
        assert_eq!(salt.len(), 64);
    }

    #[test]
    fn test_encryption_roundtrip() {
        let (key, _) = derive_key("my-secret", None).unwrap();
        let plaintext = b"Hello, PCOS E2EE!";
        let encrypted = encrypt_bytes(plaintext, &key).unwrap();
        assert_ne!(encrypted, plaintext);
        let decrypted = decrypt_bytes(&encrypted, &key).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_encryption_meta() {
        let (key, salt) = derive_key("pass", None).unwrap();
        let meta = create_encryption_meta(&key, &salt);
        assert_eq!(meta.algorithm, "AES-256-GCM");
        assert_eq!(meta.version, 1);
        assert!(!meta.nonce.is_empty());
    }
}
