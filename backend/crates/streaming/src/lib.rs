//! Video/Audio adaptive streaming crate.
//!
//! Provides HLS adaptive bitrate streaming via Docker-based FFmpeg transcoding.
//! No local FFmpeg install required — all transcoding runs in the `pcos-transcoder` container.

pub mod handlers;
pub mod service;

use axum::{
    routing::{get, post},
    Router,
};
use pcos_common::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/transcode", post(handlers::transcode))
        .route("/jobs", get(handlers::list_jobs))
        .route("/jobs/:id", get(handlers::get_job))
        .route("/stream/:id", get(handlers::stream_url))
        .route("/probe/:file_id", post(handlers::probe))
}
