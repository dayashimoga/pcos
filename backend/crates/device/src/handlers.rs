use crate::models::{CreatePairingRequest, RedeemPairingRequest, RegisterDeviceRequest};
use crate::service;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use uuid::Uuid;
use validator::Validate;

/// POST /api/v1/devices
/// Register a new device for the authenticated user.
pub async fn register_device(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<RegisterDeviceRequest>,
) -> Result<impl IntoResponse, AppError> {
    req.validate()
        .map_err(|e| AppError::Validation(e.to_string()))?;

    let device = service::register_device(state.db.pool(), auth.claims.sub, req).await?;

    Ok((StatusCode::CREATED, Json(device)))
}

/// GET /api/v1/devices
/// List all devices for the authenticated user.
pub async fn list_devices(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let devices = service::list_devices(state.db.pool(), auth.claims.sub).await?;
    Ok(Json(devices))
}

/// DELETE /api/v1/devices/:id
/// Remove a device (must belong to the authenticated user).
pub async fn remove_device(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(device_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    service::remove_device(state.db.pool(), auth.claims.sub, device_id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// PUT /api/v1/devices/:id/heartbeat
/// Update device online status and last-seen timestamp.
pub async fn heartbeat(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(device_id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    service::heartbeat(state.db.pool(), auth.claims.sub, device_id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// POST /api/v1/devices/pair
/// Create a new 5-minute QR pairing session.
pub async fn create_pairing(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<CreatePairingRequest>,
) -> Result<impl IntoResponse, AppError> {
    let session =
        service::create_pairing_session(state.db.pool(), &state, auth.claims.sub, req).await?;
    Ok((StatusCode::CREATED, Json(session)))
}

/// POST /api/v1/devices/pair/redeem
/// Redeem pairing OTP/token from scanning a QR code to enroll device.
pub async fn redeem_pairing(
    State(state): State<AppState>,
    Json(req): Json<RedeemPairingRequest>,
) -> Result<impl IntoResponse, AppError> {
    req.validate()
        .map_err(|e| AppError::Validation(e.to_string()))?;

    let response = service::redeem_pairing_session(state.db.pool(), &state, req).await?;
    Ok((StatusCode::OK, Json(response)))
}
