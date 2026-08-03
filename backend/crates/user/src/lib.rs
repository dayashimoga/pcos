pub mod admin;
pub mod handlers;
pub mod models;
pub mod service;

use axum::{
    routing::{get, put},
    Router,
};
use pcos_common::AppState;

/// Build the user router with profile and admin endpoints.
pub fn router() -> Router<AppState> {
    Router::new()
        .route(
            "/api/v1/users/me",
            get(handlers::get_profile).put(handlers::update_profile),
        )
        // Admin routes (role-guarded inside handlers)
        .route("/api/v1/admin/users", get(admin::list_users))
        .route("/api/v1/admin/users/role", put(admin::update_role))
        .route("/api/v1/admin/users/quota", put(admin::update_quota))
        .route("/api/v1/admin/system", get(admin::system_stats))
}
