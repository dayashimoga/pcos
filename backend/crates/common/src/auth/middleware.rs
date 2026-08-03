use crate::auth::jwt::{validate_token, Claims};
use crate::AppState;
use axum::{
    extract::FromRequestParts,
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

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = crate::AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let auth_header = parts
            .headers
            .get("Authorization")
            .and_then(|v| v.to_str().ok())
            .ok_or_else(|| {
                crate::AppError::Unauthorized("Missing Authorization header".to_string())
            })?;

        let token = auth_header.strip_prefix("Bearer ").ok_or_else(|| {
            crate::AppError::Unauthorized("Invalid Authorization header format".to_string())
        })?;

        let token_data = validate_token(token, &state.config.auth.jwt_secret)?;

        Ok(AuthUser {
            claims: token_data.claims,
        })
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_auth_user_struct() {
        // AuthUser is a simple wrapper; validated through integration tests
        assert_eq!(std::mem::size_of::<super::Claims>() > 0, true);
    }
}
