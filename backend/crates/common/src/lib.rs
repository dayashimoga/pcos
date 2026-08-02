pub mod auth;
pub mod config;
pub mod db;
pub mod error;

pub use config::AppConfig;
pub use db::DatabasePool;
pub use error::AppError;

use std::sync::Arc;

/// Shared application state passed to all handlers via Axum's State extractor.
#[derive(Clone)]
pub struct AppState {
    pub db: DatabasePool,
    pub config: AppConfig,
    /// Optional Tantivy search index — None if index fails to initialize.
    pub search_index: Option<Arc<dyn std::any::Any + Send + Sync>>,
}

impl AppState {
    pub fn new(db: DatabasePool, config: AppConfig) -> Self {
        Self { db, config, search_index: None }
    }

    pub fn with_search_index(mut self, index: Arc<dyn std::any::Any + Send + Sync>) -> Self {
        self.search_index = Some(index);
        self
    }
}
