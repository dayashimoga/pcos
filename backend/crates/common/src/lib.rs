pub mod auth;
pub mod config;
pub mod db;
pub mod error;

pub use config::AppConfig;
pub use db::DatabasePool;
pub use error::AppError;

/// Shared application state passed to all handlers via Axum's State extractor.
#[derive(Clone)]
pub struct AppState {
    pub db: DatabasePool,
    pub config: AppConfig,
}

impl AppState {
    pub fn new(db: DatabasePool, config: AppConfig) -> Self {
        Self { db, config }
    }
}
