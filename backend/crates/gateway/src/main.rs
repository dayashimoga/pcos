use axum::extract::DefaultBodyLimit;
use axum::{http::Method, routing::get, Json, Router};
use pcos_common::AppState;
use serde::Serialize;
use std::time::Duration;
use tower_http::cors::CorsLayer;
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::trace::TraceLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[derive(Serialize)]
struct HealthResponse {
    status: String,
    version: String,
    uptime_secs: u64,
}

static START_TIME: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    START_TIME.get_or_init(std::time::Instant::now);

    // Load .env file if present (development)
    dotenvy::dotenv().ok();

    // Initialize structured logging
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "pcos=info,tower_http=info,sqlx=warn".into()),
        )
        .with(tracing_subscriber::fmt::layer().json())
        .init();

    tracing::info!("Starting PCOS server...");

    // Load configuration
    let config = pcos_common::AppConfig::load()
        .map_err(|e| anyhow::anyhow!("Failed to load configuration: {e}"))?;

    tracing::info!(host = %config.server.host, port = %config.server.port, "Configuration loaded");

    // Ensure storage directory exists
    let storage_path = std::path::Path::new(&config.storage.base_path);
    if !storage_path.exists() {
        tokio::fs::create_dir_all(storage_path).await?;
        tracing::info!(path = %config.storage.base_path, "Created storage directory");
    }

    // Connect to database
    let db = pcos_common::DatabasePool::connect(&config.database).await?;

    // Run migrations
    db.run_migrations().await?;

    // Build application state
    let state = AppState::new(db.clone(), config.clone());

    // Build CORS layer — configurable origins
    let cors = build_cors_layer();

    // Upload body limit from config (default 10GB)
    let upload_limit = (config.storage.max_upload_size_mb * 1024 * 1024) as usize;

    // Build the application router by merging all service routers
    let app = Router::new()
        // Health check (no auth required)
        .route("/health", get(health_check))
        .route("/api/v1/health", get(health_check))
        // Service routes
        .merge(pcos_auth::router())
        .merge(pcos_user::router())
        .merge(pcos_device::router())
        .merge(pcos_file_metadata::router())
        .merge(pcos_search::router())
        .merge(pcos_ai::router())
        .merge(pcos_sharing::router())
        .merge(pcos_sync_engine::router())
        .merge(pcos_notification::router())
        .merge(pcos_worker::router())
        .merge(pcos_backup::router())
        .merge(pcos_analytics::router())
        // Middleware layers (order matters — outermost first)
        .layer(DefaultBodyLimit::max(upload_limit))
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .with_state(state.clone());

    // Start background tasks
    spawn_background_tasks(state);

    // Bind and serve
    let addr = format!("{}:{}", config.server.host, config.server.port);
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!("PCOS server listening on {}", addr);

    // Graceful shutdown
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    tracing::info!("PCOS server stopped");
    Ok(())
}

/// Health check endpoint returning server status.
async fn health_check() -> Json<HealthResponse> {
    let uptime = START_TIME.get().map(|t| t.elapsed().as_secs()).unwrap_or(0);
    Json(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        uptime_secs: uptime,
    })
}

/// Build CORS layer from environment or defaults.
fn build_cors_layer() -> CorsLayer {
    let origins = std::env::var("PCOS_CORS_ORIGINS").unwrap_or_default();

    if origins.is_empty() || origins == "*" {
        // Development mode — allow all
        CorsLayer::new()
            .allow_origin(tower_http::cors::Any)
            .allow_methods([Method::GET, Method::POST, Method::PUT, Method::DELETE, Method::PATCH])
            .allow_headers(tower_http::cors::Any)
            .max_age(Duration::from_secs(3600))
    } else {
        // Production mode — restrict origins
        let allowed: Vec<_> = origins.split(',')
            .filter_map(|s| s.trim().parse().ok())
            .collect();

        CorsLayer::new()
            .allow_origin(allowed)
            .allow_methods([Method::GET, Method::POST, Method::PUT, Method::DELETE, Method::PATCH])
            .allow_headers(tower_http::cors::Any)
            .allow_credentials(true)
            .max_age(Duration::from_secs(3600))
    }
}

/// Spawn background maintenance tasks.
fn spawn_background_tasks(state: AppState) {
    // Task 1: Clean expired refresh tokens every hour
    {
        let pool = state.db.pool().clone();
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(3600));
            loop {
                interval.tick().await;
                match sqlx::query("DELETE FROM refresh_tokens WHERE expires_at < NOW() OR revoked = true")
                    .execute(&pool).await
                {
                    Ok(r) => {
                        if r.rows_affected() > 0 {
                            tracing::info!(count = r.rows_affected(), "Cleaned expired refresh tokens");
                        }
                    }
                    Err(e) => tracing::error!(error = %e, "Failed to clean expired tokens"),
                }
            }
        });
    }

    // Task 2: Auto-delete trashed items older than 30 days (every 6 hours)
    {
        let pool = state.db.pool().clone();
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(6 * 3600));
            loop {
                interval.tick().await;
                match sqlx::query("DELETE FROM file_entries WHERE is_trashed = true AND updated_at < NOW() - INTERVAL '30 days'")
                    .execute(&pool).await
                {
                    Ok(r) => {
                        if r.rows_affected() > 0 {
                            tracing::info!(count = r.rows_affected(), "Auto-deleted old trashed items");
                        }
                    }
                    Err(e) => tracing::error!(error = %e, "Failed to clean trash"),
                }
            }
        });
    }

    // Task 3: Deactivate expired share links (every hour)
    {
        let pool = state.db.pool().clone();
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(3600));
            loop {
                interval.tick().await;
                let _ = sqlx::query("UPDATE share_links SET is_active = false WHERE expires_at < NOW() AND is_active = true")
                    .execute(&pool).await;
            }
        });
    }

    tracing::info!("Background tasks started (token cleanup, trash cleanup, share expiry)");
}

/// Listen for shutdown signals (Ctrl+C or SIGTERM).
async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("Failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("Failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => { tracing::info!("Received Ctrl+C, shutting down..."); },
        _ = terminate => { tracing::info!("Received SIGTERM, shutting down..."); },
    }
}
