pub mod handlers;
pub mod ldap;
pub mod mfa;
pub mod models;
pub mod oidc;
pub mod recovery;
pub mod service;

use axum::{
    routing::{get, post},
    Router,
};
use pcos_common::AppState;

/// Build the auth router with all authentication endpoints.
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/auth/register", post(handlers::register))
        .route("/api/v1/auth/login", post(handlers::login))
        .route("/api/v1/auth/refresh", post(handlers::refresh_token))
        .route("/api/v1/auth/logout", post(handlers::logout))
        // Emergency Account Recovery (BIP-39 break glass)
        .route(
            "/api/v1/auth/recovery/generate",
            post(recovery::generate_recovery_phrase),
        )
        .route(
            "/api/v1/auth/recovery/verify",
            post(recovery::verify_recovery_phrase),
        )
        // MFA/TOTP
        .route("/api/v1/auth/mfa/setup", post(mfa::setup_totp))
        .route("/api/v1/auth/mfa/verify", post(mfa::verify_totp_setup))
        .route("/api/v1/auth/mfa/disable", post(mfa::disable_totp))
        .route("/api/v1/auth/mfa/status", get(mfa::mfa_status))
}
