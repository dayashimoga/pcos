pub mod admin;
pub mod family;
pub mod handlers;
pub mod models;
pub mod service;

use axum::{
    routing::{delete, get, post, put},
    Router,
};
use pcos_common::AppState;

/// Build the user router with profile, admin, and family endpoints.
pub fn router() -> Router<AppState> {
    Router::new()
        .route(
            "/api/v1/users/me",
            get(handlers::get_profile).put(handlers::update_profile),
        )
        .route("/api/v1/users/me/password", put(handlers::change_password))
        // Family Clouds & Multi-Tenant Isolation
        .route(
            "/api/v1/family/clouds",
            post(family::create_cloud).get(family::list_clouds),
        )
        .route("/api/v1/family/members", get(family::list_members))
        .route("/api/v1/family/members/invite", post(family::invite_member))
        .route(
            "/api/v1/family/members/:id/role",
            put(family::update_member_role),
        )
        .route(
            "/api/v1/family/members/:id/quota",
            put(family::update_member_quota),
        )
        .route("/api/v1/family/members/:id", delete(family::delete_member))
        // Admin routes (role-guarded inside handlers)
        .route("/api/v1/admin/users", get(admin::list_users))
        .route("/api/v1/admin/users/role", put(admin::update_role))
        .route("/api/v1/admin/users/quota", put(admin::update_quota))
        .route("/api/v1/admin/system", get(admin::system_stats))
}
