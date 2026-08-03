pub mod extraction;
pub mod handlers;
pub mod index;
pub mod service;

use axum::{
    routing::{get, post},
    Router,
};
use pcos_common::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/search", get(handlers::search))
        .route("/api/v1/search/suggest", get(handlers::suggest))
        .route("/api/v1/search/reindex", post(handlers::reindex))
        .route("/api/v1/search/extract/:id", post(handlers::extract_text))
}
