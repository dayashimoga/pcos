use serde::Deserialize;

/// Top-level application configuration loaded from environment variables.
/// Environment variables use the prefix `PCOS_` and double underscores for nesting.
/// Example: `PCOS_SERVER__PORT=8080` maps to `server.port`.
#[derive(Debug, Clone, Deserialize)]
pub struct AppConfig {
    pub server: ServerConfig,
    pub database: DatabaseConfig,
    pub auth: AuthConfig,
    pub redis: RedisConfig,
    pub storage: StorageConfig,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DatabaseConfig {
    pub url: String,
    pub max_connections: u32,
    pub min_connections: u32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AuthConfig {
    pub jwt_secret: String,
    pub access_token_expiry_secs: i64,
    pub refresh_token_expiry_secs: i64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RedisConfig {
    pub url: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct StorageConfig {
    pub base_path: String,
    pub max_upload_size_mb: u64,
}

impl AppConfig {
    /// Load configuration from environment variables.
    /// Uses the `PCOS_` prefix with `__` as the separator for nested keys.
    pub fn load() -> Result<Self, config::ConfigError> {
        let cfg = config::Config::builder()
            .set_default("server.host", "0.0.0.0")?
            .set_default("server.port", 8080)?
            .set_default("database.url", "postgresql://pcos:pcos@localhost:5432/pcos")?
            .set_default("database.max_connections", 20)?
            .set_default("database.min_connections", 5)?
            .set_default(
                "auth.jwt_secret",
                "default-jwt-secret-key-must-be-changed-in-production-32-chars",
            )?
            .set_default("auth.access_token_expiry_secs", 900)?
            .set_default("auth.refresh_token_expiry_secs", 604800)?
            .set_default("redis.url", "redis://localhost:6379")?
            .set_default("storage.base_path", "./data/storage")?
            .set_default("storage.max_upload_size_mb", 10240)?
            .add_source(
                config::Environment::with_prefix("PCOS")
                    .prefix_separator("_")
                    .separator("__")
                    .try_parsing(true),
            )
            .build()?;

        let mut config: Self = cfg.try_deserialize()?;

        // Environment overrides for standard DATABASE_URL / JWT_SECRET if provided directly
        if let Ok(db_url) = std::env::var("DATABASE_URL") {
            if !db_url.is_empty() {
                config.database.url = db_url;
            }
        }
        if let Ok(jwt_secret) = std::env::var("JWT_SECRET") {
            if !jwt_secret.is_empty() {
                config.auth.jwt_secret = jwt_secret;
            }
        }

        Ok(config)
    }
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            host: "0.0.0.0".to_string(),
            port: 8080,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_defaults() {
        // Clear any existing env vars that might interfere
        std::env::set_var(
            "PCOS_DATABASE__URL",
            "postgresql://test:test@localhost/test",
        );
        std::env::set_var(
            "PCOS_AUTH__JWT_SECRET",
            "test-secret-that-is-long-enough-for-testing-purposes-64-chars!!",
        );

        let config = AppConfig::load().expect("Failed to load config");
        assert!(!config.auth.jwt_secret.is_empty());
        assert!(!config.database.url.is_empty());
        assert!(config.server.port > 0);
        assert!(config.database.max_connections > 0);
    }
}
