pub mod email;
pub mod handlers;

use axum::{routing::{get, post, put}, Router};
use pcos_common::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/notifications", get(handlers::list_notifications).post(handlers::create_notification))
        .route("/api/v1/notifications/:id/read", put(handlers::mark_read))
        .route("/api/v1/notifications/read-all", post(handlers::mark_all_read))
        .route("/api/v1/notifications/unread-count", get(handlers::unread_count))
}
