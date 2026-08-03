use crate::auth::jwt::{validate_token, Claims};
use crate::AppState;
use axum::{extract::FromRequestParts, http::request::Parts};
use std::future::Future;

/// Axum extractor that validates the JWT Bearer token from the Authorization header
/// and provides the authenticated user's claims to handlers.
#[derive(Debug, Clone)]
pub struct AuthUser {
    pub claims: Claims,
}

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = crate::AppError;

    fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> impl Future<Output = Result<Self, Self::Rejection>> + Send {
        let auth_header = parts
            .headers
            .get("Authorization")
            .and_then(|v| v.to_str().ok())
            .map(|s| s.to_string());
        let jwt_secret = state.config.auth.jwt_secret.clone();

        async move {
            let header = auth_header.ok_or_else(|| {
                crate::AppError::Unauthorized("Missing Authorization header".to_string())
            })?;

            let token = header.strip_prefix("Bearer ").ok_or_else(|| {
                crate::AppError::Unauthorized("Invalid Authorization header format".to_string())
            })?;

            let token_data = validate_token(token, &jwt_secret)?;

            Ok(AuthUser {
                claims: token_data.claims,
            })
        }
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_auth_user_struct() {
        assert!(std::mem::size_of::<super::Claims>() > 0);
    }
}
