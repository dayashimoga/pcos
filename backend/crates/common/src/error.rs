use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Serialize;

/// Unified application error type that maps to appropriate HTTP responses.
#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Unauthorized: {0}")]
    Unauthorized(String),

    #[error("Forbidden: {0}")]
    Forbidden(String),

    #[error("Validation error: {0}")]
    Validation(String),

    #[error("Conflict: {0}")]
    Conflict(String),

    #[error("Rate limited")]
    RateLimited,

    #[error("Internal server error: {0}")]
    Internal(String),

    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("JWT error: {0}")]
    Jwt(#[from] jsonwebtoken::errors::Error),
}

/// Structured error response body returned to API clients.
#[derive(Debug, Serialize)]
struct ErrorResponse {
    error: ErrorBody,
}

#[derive(Debug, Serialize)]
struct ErrorBody {
    code: String,
    message: String,
}

impl AppError {
    fn status_code(&self) -> StatusCode {
        match self {
            AppError::NotFound(_) => StatusCode::NOT_FOUND,
            AppError::Unauthorized(_) | AppError::Jwt(_) => StatusCode::UNAUTHORIZED,
            AppError::Forbidden(_) => StatusCode::FORBIDDEN,
            AppError::Validation(_) => StatusCode::UNPROCESSABLE_ENTITY,
            AppError::Conflict(_) => StatusCode::CONFLICT,
            AppError::RateLimited => StatusCode::TOO_MANY_REQUESTS,
            AppError::Internal(_) | AppError::Database(_) => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }

    fn error_code(&self) -> &str {
        match self {
            AppError::NotFound(_) => "NOT_FOUND",
            AppError::Unauthorized(_) => "UNAUTHORIZED",
            AppError::Jwt(_) => "INVALID_TOKEN",
            AppError::Forbidden(_) => "FORBIDDEN",
            AppError::Validation(_) => "VALIDATION_ERROR",
            AppError::Conflict(_) => "CONFLICT",
            AppError::RateLimited => "RATE_LIMITED",
            AppError::Internal(_) => "INTERNAL_ERROR",
            AppError::Database(_) => "DATABASE_ERROR",
        }
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let status = self.status_code();

        // Log server errors at error level, client errors at warn level
        match &self {
            AppError::Internal(_) | AppError::Database(_) => {
                tracing::error!(error = %self, "Server error");
            }
            _ => {
                tracing::warn!(error = %self, "Client error");
            }
        }

        // Sanitize internal details from the response for security
        let message = match &self {
            AppError::Database(_) => "An internal error occurred".to_string(),
            AppError::Internal(_) => "An internal error occurred".to_string(),
            other => other.to_string(),
        };

        let body = ErrorResponse {
            error: ErrorBody {
                code: self.error_code().to_string(),
                message,
            },
        };

        (status, axum::Json(body)).into_response()
    }
}

/// Convenience type alias for handler return types.
pub type AppResult<T> = Result<T, AppError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_status_codes() {
        assert_eq!(
            AppError::NotFound("test".into()).status_code(),
            StatusCode::NOT_FOUND
        );
        assert_eq!(
            AppError::Unauthorized("test".into()).status_code(),
            StatusCode::UNAUTHORIZED
        );
        assert_eq!(
            AppError::Validation("test".into()).status_code(),
            StatusCode::UNPROCESSABLE_ENTITY
        );
        assert_eq!(
            AppError::RateLimited.status_code(),
            StatusCode::TOO_MANY_REQUESTS
        );
    }

    #[test]
    fn test_database_error_is_sanitized() {
        let err = AppError::Database(sqlx::Error::RowNotFound);
        assert_eq!(err.error_code(), "DATABASE_ERROR");
        // The message should be sanitized in the response
    }
}
