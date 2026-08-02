pub mod handlers;
pub mod models;
pub mod service;

use axum::{
    routing::{delete, get, post, put},
    Router,
};
use pcos_common::AppState;

/// Build the device router with device management endpoints.
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/devices", post(handlers::register_device).get(handlers::list_devices))
        .route("/api/v1/devices/:id", delete(handlers::remove_device))
        .route("/api/v1/devices/:id/heartbeat", put(handlers::heartbeat))
}
