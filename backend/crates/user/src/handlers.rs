use crate::models::UpdateProfileRequest;
use crate::service;
use axum::extract::State;
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use validator::Validate;

/// GET /api/v1/users/me
/// Returns the authenticated user's profile.
pub async fn get_profile(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let profile = service::get_profile(state.db.pool(), auth.claims.sub).await?;
    Ok(Json(profile))
}

/// PUT /api/v1/users/me
/// Update the authenticated user's profile.
pub async fn update_profile(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<UpdateProfileRequest>,
) -> Result<impl IntoResponse, AppError> {
    req.validate()
        .map_err(|e| AppError::Validation(e.to_string()))?;

    let profile = service::update_profile(state.db.pool(), auth.claims.sub, req).await?;
    Ok(Json(profile))
}
