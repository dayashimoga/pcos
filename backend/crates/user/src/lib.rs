pub mod handlers;
pub mod models;
pub mod service;

use axum::{routing::{get, put}, Router};
use pcos_common::AppState;

/// Build the user router with profile endpoints.
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/users/me", get(handlers::get_profile).put(handlers::update_profile))
}
