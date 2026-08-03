pub mod handlers;
pub mod models;
pub mod service;

use axum::{
    routing::{get, post},
    Router,
};
use pcos_common::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/sync/ws", get(handlers::sync_websocket))
        .route("/api/v1/sync/status", get(handlers::sync_status))
        .route("/api/v1/sync/changes", get(handlers::get_changes))
        .route("/api/v1/sync/resolve", post(handlers::resolve_conflict))
        .route(
            "/api/v1/sync/folders",
            get(handlers::list_sync_folders).post(handlers::add_sync_folder),
        )
        .route(
            "/api/v1/sync/folders/:id",
            axum::routing::delete(handlers::remove_sync_folder),
        )
}
