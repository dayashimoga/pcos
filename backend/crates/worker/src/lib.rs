pub mod handlers;

use axum::{routing::get, Router};
use pcos_common::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/jobs", get(handlers::list_jobs))
        .route("/api/v1/jobs/stats", get(handlers::job_stats))
}
