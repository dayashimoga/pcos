//! PCOS Emergency Account Recovery
//!
//! Generates and verifies BIP-39 12-word mnemonic phrases for break-glass
//! account recovery and password reset without third-party email/SMS dependencies.

use axum::extract::State;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::auth::password::hash_password;
use pcos_common::error::AppError;
use pcos_common::AppState;
use rand::Rng;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

const BIP39_WORDS: &[&str] = &[
    "abandon", "ability", "able", "about", "above", "absent", "absorb", "abstract",
    "absurd", "abuse", "access", "accident", "account", "accuse", "achieve", "acid",
    "acoustic", "acquire", "across", "act", "action", "actor", "actress", "actual",
    "adapt", "add", "addict", "address", "adjust", "admit", "adult", "advance",
    "advice", "aerobic", "affair", "afford", "afraid", "again", "age", "agent",
    "agree", "ahead", "aim", "air", "airport", "aisle", "alarm", "album",
    "alcohol", "alert", "alien", "all", "alley", "allow", "almost", "alone",
    "alpha", "already", "also", "alter", "always", "amaze", "amber", "ambulance",
    "ambush", "amend", "among", "amount", "amuse", "analyst", "anchor", "ancient",
    "anger", "angle", "angry", "animal", "ankle", "announce", "annual", "another",
    "answer", "antenna", "antique", "anxiety", "any", "apart", "apology", "appear",
    "apple", "approve", "april", "arch", "arctic", "area", "arena", "argue",
    "arm", "armed", "armor", "army", "around", "arrange", "arrest", "arrive",
    "arrow", "art", "artefact", "artist", "artwork", "ask", "aspect", "assault",
    "asset", "assist", "assume", "asthma", "athlete", "atom", "attack", "attend",
    "attitude", "attract", "auction", "audit", "august", "aunt", "author", "auto",
    "autumn", "average", "avocado", "avoid", "awake", "aware", "away", "awesome",
    "awful", "awkward", "axis", "baby", "bachelor", "bacon", "badge", "bag",
    "balance", "balcony", "ball", "bamboo", "banana", "banner", "bar", "barely",
    "bargain", "barrel", "base", "basic", "basket", "battle", "beach", "bean",
    "beauty", "because", "become", "beef", "before", "begin", "behave", "behind",
    "believe", "below", "belt", "bench", "benefit", "best", "betray", "better",
    "between", "beyond", "bicycle", "bid", "bike", "bind", "biology", "bird",
    "birth", "bitter", "black", "blade", "blame", "blanket", "blast", "bleak",
    "bless", "blind", "blood", "blossom", "blouse", "blue", "blur", "blush",
    "board", "boat", "body", "boil", "bomb", "bone", "bonus", "book",
    "boost", "border", "boring", "borrow", "boss", "bottom", "bounce", "box",
    "boy", "bracket", "brain", "brand", "brass", "brave", "bread", "breeze",
    "brick", "bridge", "brief", "bright", "bring", "brisk", "broccoli", "broken",
    "bronze", "broom", "brother", "brown", "brush", "bubble", "buddy", "budget",
    "buffalo", "build", "bulb", "bulk", "bullet", "bundle", "bunker", "burden",
    "burger", "burst", "bus", "business", "busy", "butter", "buyer", "buzz",
];

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

fn hash_phrase(phrase: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(phrase.trim().to_lowercase().as_bytes());
    hex::encode(hasher.finalize())
}

/// POST /api/v1/auth/recovery/generate
pub async fn generate_recovery_phrase(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<Json<GenerateRecoveryResponse>, AppError> {
    let phrase = {
        let mut rng = rand::thread_rng();
        let words: Vec<&str> = (0..12)
            .map(|_| BIP39_WORDS[rng.gen_range(0..BIP39_WORDS.len())])
            .collect();
        words.join(" ")
    };

    let rec_hash = hash_phrase(&phrase);
    let key_id = format!("rec_{}", Uuid::new_v4());

    sqlx::query(
        "INSERT INTO recovery_keys (id, user_id, recovery_hash, hint, is_used, created_at) VALUES ($1, $2, $3, $4, false, NOW())"
    )
    .bind(&key_id)
    .bind(auth.claims.sub)
    .bind(&rec_hash)
    .bind("12-word mnemonic phrase")
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
    fn test_hash_phrase_deterministic() {
        let phrase = "abandon ability able about above absent absorb abstract absurd abuse access accident";
        let h1 = hash_phrase(phrase);
        let h2 = hash_phrase(&phrase.to_uppercase());
        assert_eq!(h1, h2);
        assert_eq!(h1.len(), 64);
    }
}
