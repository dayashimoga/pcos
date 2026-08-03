use crate::models::{
    LoginRequest, LogoutRequest, MessageResponse, RefreshTokenRequest, RegisterRequest,
};
use crate::service;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::error::AppError;
use pcos_common::AppState;
use validator::Validate;

/// POST /api/v1/auth/register
/// Create a new user account with email, display name, and password.
pub async fn register(
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> Result<impl IntoResponse, AppError> {
    req.validate()
        .map_err(|e| AppError::Validation(e.to_string()))?;

    let response = service::register(state.db.pool(), &state, req).await?;

    Ok((StatusCode::CREATED, Json(response)))
}

/// POST /api/v1/auth/login
/// Authenticate with email and password, receive JWT tokens.
pub async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> Result<impl IntoResponse, AppError> {
    req.validate()
        .map_err(|e| AppError::Validation(e.to_string()))?;

    let response = service::login(state.db.pool(), &state, req).await?;

    Ok((StatusCode::OK, Json(response)))
}

/// POST /api/v1/auth/refresh
/// Exchange a valid refresh token for a new token pair (rotation).
pub async fn refresh_token(
    State(state): State<AppState>,
    Json(req): Json<RefreshTokenRequest>,
) -> Result<impl IntoResponse, AppError> {
    let tokens = service::refresh(state.db.pool(), &state, req).await?;

    Ok((StatusCode::OK, Json(tokens)))
}

/// POST /api/v1/auth/logout
/// Revoke the provided refresh token.
pub async fn logout(
    State(state): State<AppState>,
    Json(req): Json<LogoutRequest>,
) -> Result<impl IntoResponse, AppError> {
    service::logout(state.db.pool(), req).await?;

    Ok((
        StatusCode::OK,
        Json(MessageResponse {
            message: "Logged out successfully".to_string(),
        }),
    ))
}
