use crate::models::{
    ApprovePairingRequest, ClaimPairingRequest, CreatePairingRequest, RedeemPairingRequest,
    RegisterDeviceRequest,
};
use crate::service;
use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use serde::Deserialize;
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

/// POST /api/v1/devices/pair/claim
/// Mobile device claims a pairing code and submits candidate device metadata for approval.
pub async fn claim_pairing(
    Json(req): Json<ClaimPairingRequest>,
) -> Result<impl IntoResponse, AppError> {
    req.validate()
        .map_err(|e| AppError::Validation(e.to_string()))?;

    let response = service::claim_pairing_session(req).await?;
    Ok((StatusCode::OK, Json(response)))
}

/// POST /api/v1/devices/pair/approve
/// Web/Desktop user approves or rejects the candidate device.
pub async fn approve_pairing(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<ApprovePairingRequest>,
) -> Result<impl IntoResponse, AppError> {
    let response =
        service::approve_pairing_session(state.db.pool(), &state, auth.claims.sub, req).await?;
    Ok((StatusCode::OK, Json(response)))
}

#[derive(Debug, Deserialize)]
pub struct PairingStatusQuery {
    pub code: Option<String>,
    pub token: Option<String>,
}

/// GET /api/v1/devices/pair/status
/// Check real-time pairing status (used by web to see incoming connection request, and mobile to see approval).
pub async fn get_pairing_status(
    Query(query): Query<PairingStatusQuery>,
) -> Result<impl IntoResponse, AppError> {
    let key = query
        .token
        .as_deref()
        .or(query.code.as_deref())
        .ok_or_else(|| {
            AppError::Validation("Either token or code query parameter is required".to_string())
        })?;

    let status = service::get_pairing_status(key).await?;
    Ok(Json(status))
}

/// POST /api/v1/devices/pair/redeem
/// Redeem pairing OTP/token to retrieve session tokens once approved (or direct single-step).
pub async fn redeem_pairing(
    State(state): State<AppState>,
    Json(req): Json<RedeemPairingRequest>,
) -> Result<impl IntoResponse, AppError> {
    req.validate()
        .map_err(|e| AppError::Validation(e.to_string()))?;

    let response = service::redeem_pairing_session(state.db.pool(), &state, req).await?;
    Ok((StatusCode::OK, Json(response)))
}
