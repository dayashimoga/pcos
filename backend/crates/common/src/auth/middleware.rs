use crate::auth::jwt::{validate_token, Claims};
use crate::AppState;
use axum::{
    async_trait,
    extract::{FromRef, FromRequestParts},
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

#[async_trait]
impl<S> FromRequestParts<S> for AuthUser
where
    AppState: FromRef<S>,
    S: Send + Sync,
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

        let token = auth_header.strip_prefix("Bearer ").ok_or_else(|| {
            crate::AppError::Unauthorized("Invalid Authorization header format".to_string())
        })?;

        let token_data = validate_token(token, &app_state.config.auth.jwt_secret)?;

        Ok(AuthUser {
            claims: token_data.claims,
        })
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_auth_user_struct() {
        assert!(std::mem::size_of::<super::Claims>() > 0);
    }
}
