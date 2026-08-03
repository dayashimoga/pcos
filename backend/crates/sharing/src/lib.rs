pub mod handlers;
pub mod models;
pub mod service;

use axum::{
    routing::{delete, get, post, put},
    Router,
};
use pcos_common::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route(
            "/api/v1/shares",
            post(handlers::create_share).get(handlers::list_shares),
        )
        .route(
            "/api/v1/shares/:id",
            get(handlers::get_share)
                .put(handlers::update_share)
                .delete(handlers::delete_share),
        )
        .route("/api/v1/shared/:token", get(handlers::access_shared))
        .route(
            "/api/v1/shared/:token/download",
            get(handlers::download_shared),
        )
}
