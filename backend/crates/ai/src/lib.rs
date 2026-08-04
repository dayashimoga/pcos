pub mod handlers;
pub mod provider;
pub mod service;

use axum::{
    routing::{get, post},
    Router,
};
use pcos_common::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/ai/tag", post(handlers::auto_tag))
        .route("/api/v1/ai/duplicates", get(handlers::find_duplicates))
        .route("/api/v1/ai/classify", post(handlers::classify_file))
        .route("/api/v1/ai/smart-search", get(handlers::smart_search))
        .route("/api/v1/ai/status", get(handlers::ai_status))
}
