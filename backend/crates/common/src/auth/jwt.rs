use crate::config::AuthConfig;
use chrono::{Duration, Utc};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, TokenData, Validation};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// JWT claims embedded in access tokens.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    /// Subject (user ID)
    pub sub: Uuid,
    /// User email
    pub email: String,
    /// Issued at (Unix timestamp)
    pub iat: i64,
    /// Expiration (Unix timestamp)
    pub exp: i64,
    /// JWT ID (unique token identifier)
    pub jti: Uuid,
}

/// A pair of access and refresh tokens returned on authentication.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TokenPair {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub expires_in: i64,
}

/// Generate a new access + refresh token pair for a user.
pub fn generate_token_pair(
    user_id: Uuid,
    email: &str,
    config: &AuthConfig,
) -> Result<TokenPair, jsonwebtoken::errors::Error> {
    let now = Utc::now();

    // Access token
    let access_claims = Claims {
        sub: user_id,
        email: email.to_string(),
        iat: now.timestamp(),
        exp: (now + Duration::seconds(config.access_token_expiry_secs)).timestamp(),
        jti: Uuid::new_v4(),
    };

    let access_token = encode(
        &Header::default(),
        &access_claims,
        &EncodingKey::from_secret(config.jwt_secret.as_bytes()),
    )?;

    // Refresh token (longer-lived, separate JTI for revocation tracking)
    let refresh_claims = Claims {
        sub: user_id,
        email: email.to_string(),
        iat: now.timestamp(),
        exp: (now + Duration::seconds(config.refresh_token_expiry_secs)).timestamp(),
        jti: Uuid::new_v4(),
    };

    let refresh_token = encode(
        &Header::default(),
        &refresh_claims,
        &EncodingKey::from_secret(config.jwt_secret.as_bytes()),
    )?;

    Ok(TokenPair {
        access_token,
        refresh_token,
        token_type: "Bearer".to_string(),
        expires_in: config.access_token_expiry_secs,
    })
}

/// Validate and decode a JWT token, returning the claims.
pub fn validate_token(
    token: &str,
    secret: &str,
) -> Result<TokenData<Claims>, jsonwebtoken::errors::Error> {
    let validation = Validation::default();
    decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &validation,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_config() -> AuthConfig {
        AuthConfig {
            jwt_secret: "test-secret-key-that-is-long-enough-for-hmac-sha256-algorithm!!"
                .to_string(),
            access_token_expiry_secs: 900,
            refresh_token_expiry_secs: 604800,
        }
    }

    #[test]
    fn test_generate_and_validate_token_pair() {
        let config = test_config();
        let user_id = Uuid::new_v4();
        let email = "test@example.com";

        let pair = generate_token_pair(user_id, email, &config).unwrap();
        assert_eq!(pair.token_type, "Bearer");
        assert_eq!(pair.expires_in, 900);

        // Validate access token
        let claims = validate_token(&pair.access_token, &config.jwt_secret).unwrap();
        assert_eq!(claims.claims.sub, user_id);
        assert_eq!(claims.claims.email, email);

        // Validate refresh token
        let refresh_claims = validate_token(&pair.refresh_token, &config.jwt_secret).unwrap();
        assert_eq!(refresh_claims.claims.sub, user_id);
    }

    #[test]
    fn test_invalid_token_rejected() {
        let result = validate_token("invalid.token.here", "secret");
        assert!(result.is_err());
    }

    #[test]
    fn test_wrong_secret_rejected() {
        let config = test_config();
        let pair = generate_token_pair(Uuid::new_v4(), "test@example.com", &config).unwrap();

        let result = validate_token(&pair.access_token, "wrong-secret");
        assert!(result.is_err());
    }

    #[test]
    fn test_token_claims_have_unique_jti() {
        let config = test_config();
        let user_id = Uuid::new_v4();

        let pair1 = generate_token_pair(user_id, "test@example.com", &config).unwrap();
        let pair2 = generate_token_pair(user_id, "test@example.com", &config).unwrap();

        let claims1 = validate_token(&pair1.access_token, &config.jwt_secret).unwrap();
        let claims2 = validate_token(&pair2.access_token, &config.jwt_secret).unwrap();

        assert_ne!(claims1.claims.jti, claims2.claims.jti);
    }
}
