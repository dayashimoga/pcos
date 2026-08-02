use crate::config::DatabaseConfig;
use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;

/// Wrapper around the PostgreSQL connection pool.
#[derive(Debug, Clone)]
pub struct DatabasePool {
    pool: PgPool,
}

impl DatabasePool {
    /// Create a new database connection pool from configuration.
    pub async fn connect(config: &DatabaseConfig) -> Result<Self, sqlx::Error> {
        let pool = PgPoolOptions::new()
            .max_connections(config.max_connections)
            .min_connections(config.min_connections)
            .acquire_timeout(std::time::Duration::from_secs(5))
            .idle_timeout(std::time::Duration::from_secs(600))
            .connect(&config.url)
            .await?;

        tracing::info!("Database connection pool established");
        Ok(Self { pool })
    }

    /// Run pending database migrations.
    pub async fn run_migrations(&self) -> Result<(), sqlx::migrate::MigrateError> {
        tracing::info!("Running database migrations...");
        sqlx::migrate!("../../migrations").run(&self.pool).await?;
        tracing::info!("Database migrations complete");
        Ok(())
    }

    /// Get a reference to the underlying pool for queries.
    pub fn pool(&self) -> &PgPool {
        &self.pool
    }

    /// Check database connectivity.
    pub async fn health_check(&self) -> Result<(), sqlx::Error> {
        sqlx::query("SELECT 1").execute(&self.pool).await?;
        Ok(())
    }
}
