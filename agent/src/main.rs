mod config;
mod db;
mod delta;
mod sync;
mod watcher;

use clap::Parser;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[derive(Parser)]
#[command(name = "pcos-agent", about = "PCOS Device Agent — syncs files with your Personal Cloud")]
struct Cli {
    /// Path to configuration file
    #[arg(short, long, default_value = "~/.pcos/agent.toml")]
    config: String,

    /// Run in daemon mode
    #[arg(short, long)]
    daemon: bool,

    /// Register this device with the server
    #[arg(long)]
    register: bool,

    /// Show agent status
    #[arg(long)]
    status: bool,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize logging
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| "pcos_agent=info".into()))
        .with(tracing_subscriber::fmt::layer())
        .init();

    let cli = Cli::parse();

    // Expand ~ in config path
    let config_path = shellexpand(&cli.config);

    // Load or create config
    let agent_config = config::AgentConfig::load_or_create(&config_path)?;

    tracing::info!(server = %agent_config.server_url, "PCOS Agent starting");

    // Initialize local database
    let local_db = db::LocalDb::open(&agent_config.data_dir)?;
    tracing::info!("Local database initialized");

    if cli.register {
        // Register device with server
        let device_name = hostname::get()
            .map(|h| h.to_string_lossy().to_string())
            .unwrap_or_else(|_| "Unknown Device".to_string());

        tracing::info!(name = %device_name, "Registering device...");
        let client = reqwest::Client::new();
        let resp = client.post(format!("{}/api/v1/devices", agent_config.server_url))
            .bearer_auth(&agent_config.auth_token)
            .json(&serde_json::json!({
                "name": device_name,
                "device_type": detect_device_type(),
                "os": std::env::consts::OS,
                "os_version": "",
                "agent_version": env!("CARGO_PKG_VERSION"),
            }))
            .send().await?;

        if resp.status().is_success() {
            let body: serde_json::Value = resp.json().await?;
            tracing::info!(device_id = %body["id"], "Device registered successfully");
        } else {
            tracing::error!(status = %resp.status(), "Registration failed");
        }
        return Ok(());
    }

    if cli.status {
        println!("PCOS Agent v{}", env!("CARGO_PKG_VERSION"));
        println!("Server: {}", agent_config.server_url);
        println!("Data dir: {}", agent_config.data_dir);
        println!("Sync folders: {}", agent_config.sync_folders.len());
        for folder in &agent_config.sync_folders {
            println!("  - {}", folder);
        }
        let stats = local_db.stats()?;
        println!("Cached files: {}", stats.total_files);
        println!("Pending sync: {}", stats.pending_sync);
        return Ok(());
    }

    // Start daemon mode
    tracing::info!("Starting in daemon mode");

    // Start filesystem watcher
    let watcher_handle = {
        let folders = agent_config.sync_folders.clone();
        let db = local_db.clone();
        tokio::spawn(async move {
            if let Err(e) = watcher::watch_folders(&folders, &db).await {
                tracing::error!(error = %e, "Filesystem watcher failed");
            }
        })
    };

    // Start sync loop
    let sync_handle = {
        let config = agent_config.clone();
        let db = local_db.clone();
        tokio::spawn(async move {
            sync::sync_loop(&config, &db).await;
        })
    };

    // Start heartbeat
    let heartbeat_handle = {
        let config = agent_config.clone();
        tokio::spawn(async move {
            loop {
                let client = reqwest::Client::new();
                let _ = client.put(format!("{}/api/v1/devices/{}/heartbeat", config.server_url, config.device_id))
                    .bearer_auth(&config.auth_token)
                    .send().await;
                tokio::time::sleep(std::time::Duration::from_secs(30)).await;
            }
        })
    };

    // Wait for shutdown signal
    tokio::signal::ctrl_c().await?;
    tracing::info!("Shutting down...");

    watcher_handle.abort();
    sync_handle.abort();
    heartbeat_handle.abort();

    Ok(())
}

fn detect_device_type() -> &'static str {
    // Simple heuristic
    if std::env::consts::OS == "android" || std::env::consts::OS == "ios" { "phone" }
    else { "desktop" }
}

fn shellexpand(path: &str) -> String {
    if path.starts_with('~') {
        if let Some(home) = dirs::home_dir() {
            return path.replacen('~', &home.to_string_lossy(), 1);
        }
    }
    path.to_string()
}
