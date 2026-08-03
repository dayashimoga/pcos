pub mod handlers;
pub mod service;

use axum::{
    routing::{delete, get, post},
    Router,
};
use pcos_common::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route(
            "/api/v1/backups",
            get(handlers::list_backups).post(handlers::create_backup),
        )
        .route(
            "/api/v1/backups/:id",
            get(handlers::get_backup).delete(handlers::delete_backup),
        )
        .route(
            "/api/v1/backups/:id/restore",
            post(handlers::restore_backup),
        )
        .route("/api/v1/backups/:id/verify", get(handlers::verify_backup))
        .route(
            "/api/v1/backups/retention",
            post(handlers::enforce_retention),
        )
        .route(
            "/api/v1/backups/schedules",
            get(handlers::list_schedules).post(handlers::create_schedule),
        )
        .route(
            "/api/v1/backups/schedules/:id",
            delete(handlers::delete_schedule),
        )
}
