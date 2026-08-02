pub mod handlers;
pub mod models;
pub mod s3_compat;
pub mod service;
pub mod storage;
pub mod versioning;
pub mod webdav;

use axum::{
    extract::DefaultBodyLimit,
    routing::{delete, get, post, put},
    Router,
};
use pcos_common::AppState;

/// Build the file management router.
pub fn router() -> Router<AppState> {
    Router::new()
        // Folder operations
        .route("/api/v1/folders", post(handlers::create_folder).get(handlers::list_root))
        .route("/api/v1/folders/:id", get(handlers::list_folder).put(handlers::rename_item).delete(handlers::delete_item))
        // File operations
        .route("/api/v1/files/upload", post(handlers::upload_file))
        .route("/api/v1/files/upload/chunk", post(handlers::upload_chunk))
        .route("/api/v1/files/upload/complete", post(handlers::complete_chunked_upload))
        .route("/api/v1/files/:id", get(handlers::get_file_meta).put(handlers::rename_item).delete(handlers::delete_item))
        .route("/api/v1/files/:id/download", get(handlers::download_file))
        .route("/api/v1/files/:id/preview", get(handlers::preview_file))
        .route("/api/v1/files/:id/move", put(handlers::move_item))
        // Trash operations
        .route("/api/v1/trash", get(handlers::list_trash))
        .route("/api/v1/trash/:id/restore", post(handlers::restore_from_trash))
        .route("/api/v1/trash/:id", delete(handlers::permanent_delete))
        .route("/api/v1/trash/empty", post(handlers::empty_trash))
        // Storage stats
        .route("/api/v1/storage/stats", get(handlers::storage_stats))
        // File versioning
        .route("/api/v1/files/:id/versions", get(versioning::list_versions))
        .route("/api/v1/files/:file_id/versions/:version_id/restore", post(versioning::restore_version))
        .route("/api/v1/files/:file_id/versions/:version_id/download", get(versioning::download_version))
        // Allow large uploads (10 GB default)
        .layer(DefaultBodyLimit::max(10 * 1024 * 1024 * 1024))
        // WebDAV compatibility routes
        .route("/webdav", get(webdav::propfind))
        .route("/webdav/*path", get(webdav::propfind)
            .delete(webdav::webdav_delete))
        .route("/webdav/:name", post(webdav::mkcol))
        // S3-compatible routes
        .route("/s3", get(s3_compat::list_buckets))
        .route("/s3/pcos-files", get(s3_compat::list_objects))
        .route("/s3/pcos-files/:key", get(s3_compat::head_object).delete(s3_compat::delete_object))
}
