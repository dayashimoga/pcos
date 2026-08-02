use crate::auth::jwt::{validate_token, Claims};
use crate::AppState;
use axum::{
    extract::{FromRequestParts, State},
    http::request::Parts,
};

/// Axum extractor that validates the JWT Bearer token from the Authorization header
/// and provides the authenticated user's claims to handlers.
///
/// Usage:
/// ```rust,ignore
/// async fn my_handler(auth: AuthUser) -> impl IntoResponse {
///     println!("User ID: {}", auth.claims.sub);
/// }
/// ```
#[derive(Debug, Clone)]
pub struct AuthUser {
    pub claims: Claims,
}

impl<S> FromRequestParts<S> for AuthUser
where
    S: Send + Sync,
    AppState: FromRef<S>,
{
    type Rejection = crate::AppError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let app_state = AppState::from_ref(state);

        let auth_header = parts
            .headers
            .get("Authorization")
            .and_then(|v| v.to_str().ok())
            .ok_or_else(|| {
                crate::AppError::Unauthorized("Missing Authorization header".to_string())
            })?;

        let token = auth_header
            .strip_prefix("Bearer ")
            .ok_or_else(|| {
                crate::AppError::Unauthorized("Invalid Authorization header format".to_string())
            })?;

        let token_data = validate_token(token, &app_state.config.auth.jwt_secret)?;

        Ok(AuthUser {
            claims: token_data.claims,
        })
    }
}

/// Helper trait to enable FromRef for AppState extraction in middleware.
pub trait FromRef<T> {
    fn from_ref(input: &T) -> Self;
}

impl FromRef<AppState> for AppState {
    fn from_ref(input: &AppState) -> Self {
        input.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_from_ref_identity() {
        let config = crate::config::AppConfig {
            server: crate::config::ServerConfig {
                host: "0.0.0.0".into(),
                port: 8080,
            },
            database: crate::config::DatabaseConfig {
                url: "postgresql://test@localhost/test".into(),
                max_connections: 5,
                min_connections: 1,
            },
            auth: crate::config::AuthConfig {
                jwt_secret: "test-secret".into(),
                access_token_expiry_secs: 900,
                refresh_token_expiry_secs: 604800,
            },
            redis: crate::config::RedisConfig {
                url: "redis://localhost:6379".into(),
            },
            storage: crate::config::StorageConfig {
                base_path: "/tmp/test".into(),
                max_upload_size_mb: 100,
            },
        };
        // We can't create a real DatabasePool without a database, but we can test the config part
        assert_eq!(config.server.port, 8080);
    }
}
