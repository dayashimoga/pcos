pub mod email;
pub mod handlers;
pub mod web_push;

use axum::{
    routing::{delete, get, post, put},
    Router,
};
use pcos_common::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route(
            "/api/v1/notifications",
            get(handlers::list_notifications).post(handlers::create_notification),
        )
        .route("/api/v1/notifications/:id/read", put(handlers::mark_read))
        .route(
            "/api/v1/notifications/read-all",
            post(handlers::mark_all_read),
        )
        .route(
            "/api/v1/notifications/unread-count",
            get(handlers::unread_count),
        )
        // Web Push
        .route("/api/v1/push/subscribe", post(handlers::push_subscribe))
        .route("/api/v1/push/unsubscribe", post(handlers::push_unsubscribe))
        .route("/api/v1/push/subscriptions", get(handlers::push_list))
        .route("/api/v1/push/send", post(handlers::push_send))
}
