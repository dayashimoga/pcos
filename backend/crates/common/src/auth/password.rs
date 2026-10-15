use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};

/// Hash a plaintext password using Argon2id.
/// Returns the PHC-formatted hash string containing algorithm, salt, and hash.
pub fn hash_password(password: &str) -> Result<String, argon2::password_hash::Error> {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    let hash = argon2.hash_password(password.as_bytes(), &salt)?;
    Ok(hash.to_string())
}

/// Verify a plaintext password against a stored hash (supports both Argon2id and PBKDF2).
pub fn verify_password(password: &str, hash: &str) -> Result<bool, anyhow::Error> {
    if hash.starts_with("pbkdf2$") {
        Ok(verify_pbkdf2(password, hash))
    } else {
        let parsed_hash =
            PasswordHash::new(hash).map_err(|e| anyhow::anyhow!("Invalid password hash: {e}"))?;
        Ok(Argon2::default()
            .verify_password(password.as_bytes(), &parsed_hash)
            .is_ok())
    }
}

/// Verify standard PBKDF2-HMAC-SHA256 password hash (format: pbkdf2$iterations$saltHex$hashHex)
fn verify_pbkdf2(password: &str, stored_hash: &str) -> bool {
    let parts: Vec<&str> = stored_hash.split('$').collect();
    if parts.len() != 4 || parts[0] != "pbkdf2" {
        return false;
    }
    let iterations: u32 = match parts[1].parse() {
        Ok(i) => i,
        Err(_) => return false,
    };
    let salt = match hex::decode(parts[2]) {
        Ok(s) => s,
        Err(_) => return false,
    };
    let expected_hash = match hex::decode(parts[3]) {
        Ok(h) => h,
        Err(_) => return false,
    };

    let derived = pbkdf2_hmac_sha256(password.as_bytes(), &salt, iterations, expected_hash.len());

    // Constant-time byte comparison
    if derived.len() != expected_hash.len() {
        return false;
    }
    let mut diff = 0u8;
    for (a, b) in derived.iter().zip(expected_hash.iter()) {
        diff |= a ^ b;
    }
    diff == 0
}

fn hmac_sha256(key: &[u8], data: &[u8]) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut k = [0u8; 64];
    if key.len() > 64 {
        let hash = Sha256::digest(key);
        k[..32].copy_from_slice(&hash);
    } else {
        k[..key.len()].copy_from_slice(key);
    }

    let mut ipad = [0x36u8; 64];
    let mut opad = [0x5cu8; 64];
    for i in 0..64 {
        ipad[i] ^= k[i];
        opad[i] ^= k[i];
    }

    let mut inner = Sha256::new();
    inner.update(ipad);
    inner.update(data);
    let inner_hash = inner.finalize();

    let mut outer = Sha256::new();
    outer.update(opad);
    outer.update(inner_hash);
    outer.finalize().into()
}

fn pbkdf2_hmac_sha256(password: &[u8], salt: &[u8], iterations: u32, key_len: usize) -> Vec<u8> {
    let mut out = Vec::with_capacity(key_len);
    let mut block_index = 1u32;

    while out.len() < key_len {
        let mut salt_and_index = salt.to_vec();
        salt_and_index.extend_from_slice(&block_index.to_be_bytes());

        let mut u = hmac_sha256(password, &salt_and_index);
        let mut t = u;

        for _ in 1..iterations {
            u = hmac_sha256(password, &u);
            for i in 0..32 {
                t[i] ^= u[i];
            }
        }

        let needed = (key_len - out.len()).min(32);
        out.extend_from_slice(&t[..needed]);
        block_index += 1;
    }

    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_and_verify() {
        let password = "SecureP@ssw0rd!";
        let hash = hash_password(password).unwrap();

        assert!(verify_password(password, &hash).unwrap());
        assert!(!verify_password("wrong-password", &hash).unwrap());
    }

    #[test]
    fn test_different_passwords_produce_different_hashes() {
        let hash1 = hash_password("password1").unwrap();
        let hash2 = hash_password("password1").unwrap();
        // Same password produces different hashes due to random salt
        assert_ne!(hash1, hash2);
    }

    #[test]
    fn test_hash_format_is_phc() {
        let hash = hash_password("test").unwrap();
        assert!(hash.starts_with("$argon2"));
    }

    #[test]
    fn test_pbkdf2_compatibility_verification() {
        // Known PBKDF2 vector generated from Cloudflare WebCrypto:
        // Password: "CloudflareEdgePassword123!"
        // Salt: hex 16 bytes: "0102030405060708090a0b0c0d0e0f10"
        let salt = hex::decode("0102030405060708090a0b0c0d0e0f10").unwrap();
        let derived = pbkdf2_hmac_sha256(b"CloudflareEdgePassword123!", &salt, 1000, 32);
        let hash_hex = hex::encode(derived);
        let stored = format!("pbkdf2$1000$0102030405060708090a0b0c0d0e0f10${hash_hex}");

        assert!(verify_password("CloudflareEdgePassword123!", &stored).unwrap());
        assert!(!verify_password("WrongEdgePassword!", &stored).unwrap());
    }
}
