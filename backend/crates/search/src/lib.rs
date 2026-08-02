pub mod handlers;
pub mod index;
pub mod service;

use axum::{routing::get, Router};
use pcos_common::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/search", get(handlers::search))
        .route("/api/v1/search/suggest", get(handlers::suggest))
        .route("/api/v1/search/reindex", axum::routing::post(handlers::reindex))
}
