//! Video/Audio adaptive streaming crate.
//!
//! Provides HLS adaptive bitrate streaming, playback token issuance,
//! and Range-based direct media streaming for client-compatible players.

pub mod handlers;
pub mod service;

use axum::{
    routing::{get, post},
    Router,
};
use pcos_common::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/streaming/transcode", post(handlers::transcode))
        .route("/api/v1/streaming/jobs", get(handlers::list_jobs))
        .route("/api/v1/streaming/jobs/:id", get(handlers::get_job))
        .route("/api/v1/streaming/stream/:id", get(handlers::stream_url))
        .route("/api/v1/streaming/probe/:file_id", post(handlers::probe))
        .route(
            "/api/v1/streaming/token/:file_id",
            post(handlers::generate_playback_token),
        )
        .route(
            "/api/v1/streaming/play/:token",
            get(handlers::play_with_token),
        )
        .route(
            "/api/v1/streaming/progress/:file_id",
            post(handlers::update_progress).get(handlers::get_progress),
        )
        .route(
            "/api/v1/streaming/resume",
            get(handlers::list_continue_watching),
        )
        .route(
            "/api/v1/media/history",
            get(handlers::list_continue_watching),
        )
}
