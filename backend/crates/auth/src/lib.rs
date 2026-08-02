pub mod handlers;
pub mod models;
pub mod service;

use axum::{routing::post, Router};
use pcos_common::AppState;

/// Build the auth router with all authentication endpoints.
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/auth/register", post(handlers::register))
        .route("/api/v1/auth/login", post(handlers::login))
        .route("/api/v1/auth/refresh", post(handlers::refresh_token))
        .route("/api/v1/auth/logout", post(handlers::logout))
}
