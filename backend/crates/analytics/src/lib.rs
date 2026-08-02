pub mod handlers;

use axum::{routing::get, Router};
use pcos_common::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/analytics/overview", get(handlers::overview))
        .route("/api/v1/analytics/storage", get(handlers::storage_analytics))
        .route("/api/v1/analytics/activity", get(handlers::activity_timeline))
        .route("/api/v1/analytics/file-types", get(handlers::file_type_breakdown))
        .route("/api/v1/admin/metrics", get(handlers::prometheus_metrics))
}
