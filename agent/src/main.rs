#![allow(dead_code)]

mod config;
mod connection_manager;
mod db;
mod delta;
mod disks;
mod discovery;
mod doctor;
mod enroll;
mod identity;
mod fs_handler;
mod lan_server;
mod sync;
mod transcoder;
mod watcher;

use clap::{Parser, Subcommand};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[derive(Parser)]
#[command(
    name = "pcos-agent",
    about = "PCOS Device Agent — syncs files with your Personal Cloud"
)]
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

    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// One-command device pairing and node enrollment
    Enroll {
        /// 6-digit pairing code from your PCOS Web or Mobile app (positional or prompt)
        #[arg(index = 1)]
        code: Option<String>,

        /// 6-digit pairing code flag (e.g. -c 123456)
        #[arg(short = 'c', long = "code")]
        code_flag: Option<String>,

        /// PCOS Control Plane server URL
        #[arg(
            short,
            long,
            default_value = "https://pcos-control-plane.dayashimoga.workers.dev"
        )]
        server: String,

        /// Immediately start the agent daemon after successful enrollment
        #[arg(long, alias = "daemon")]
        start: bool,
    },

    /// Run node health diagnostics (storage, networking, CGNAT, control plane, FFmpeg)
    Doctor {
        /// Storage directory to test
        #[arg(short = 'd', long, default_value = ".")]
        storage: String,

        /// PCOS Control Plane server URL
        #[arg(
            short,
            long,
            default_value = "https://pcos-control-plane.dayashimoga.workers.dev"
        )]
        server: String,
    },

    /// Start the outbound node agent service
    Start {
        /// Run in background daemon mode
        #[arg(short, long)]
        daemon: bool,
    },

    /// Display node configuration and synchronization statistics
    Status,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize logging
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "pcos_agent=info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let cli = Cli::parse();

    // Expand ~ in config path
    let config_path = shellexpand(&cli.config);

    // Handle subcommands first
    if let Some(cmd) = cli.command {
        match cmd {
            Commands::Enroll {
                code,
                code_flag,
                server,
                start,
            } => {
                let code_str = match code.or(code_flag) {
                    Some(c) if !c.trim().is_empty() => c.trim().to_string(),
                    _ => {
                        println!();
                        println!("+------------------------------------------------------------+");
                        println!("|          PCOS Physical Node Onboarding                     |");
                        println!("+------------------------------------------------------------+");
                        println!("Enter the 6-digit pairing code from your PCOS web or app screen:");
                        print!("Pairing Code > ");
                        use std::io::{self, Write};
                        io::stdout().flush().ok();
                        let mut input = String::new();
                        io::stdin().read_line(&mut input)?;
                        let trimmed = input.trim().to_string();
                        if trimmed.is_empty() {
                            anyhow::bail!("Pairing cancelled: no pairing code entered.");
                        }
                        trimmed
                    }
                };

                enroll::enroll_node_with_code(&code_str, &server, &config_path).await?;

                if !start {
                    print!("Start PCOS agent daemon now? [Y/n] > ");
                    use std::io::{self, Write};
                    io::stdout().flush().ok();
                    let mut input = String::new();
                    io::stdin().read_line(&mut input)?;
                    let ans = input.trim().to_lowercase();
                    if !ans.is_empty() && ans != "y" && ans != "yes" {
                        return Ok(());
                    }
                }
                // Fall through to daemon startup below
            }
            Commands::Doctor { storage, server } => {
                let report = doctor::DoctorReport::run_diagnostics(&storage, &server).await;
                report.print_report();
                return Ok(());
            }
            Commands::Status => {
                let agent_config = config::AgentConfig::load_or_create(&config_path)?;
                let local_db = db::LocalDb::open(&agent_config.data_dir)?;
                print_status(&agent_config, &local_db)?;
                return Ok(());
            }
            Commands::Start { daemon: _ } => {
                // proceed to start daemon
            }
        }
    }

    // Load or create config
    let mut agent_config = config::AgentConfig::load_or_create(&config_path)?;

    // If device is not enrolled yet, prompt interactively instead of failing connection
    if agent_config.auth_token.is_empty() || agent_config.device_id.is_empty() {
        println!();
        println!("+------------------------------------------------------------+");
        println!("|           PCOS Node Setup — First-Time Pairing             |");
        println!("+------------------------------------------------------------+");
        println!("This machine is not yet paired with your PCOS personal cloud.");
        println!("1. Open: {}/#/devices", agent_config.server_url);
        println!("2. Click [Connect Physical Device] to get your 6-digit code.");
        println!();
        print!("Enter 6-digit pairing code > ");
        use std::io::{self, Write};
        io::stdout().flush().ok();
        let mut input = String::new();
        io::stdin().read_line(&mut input)?;
        let code = input.trim();
        if code.is_empty() {
            anyhow::bail!("Pairing cancelled: no pairing code entered.");
        }
        enroll::enroll_node_with_code(code, &agent_config.server_url, &config_path).await?;
        agent_config = config::AgentConfig::load_or_create(&config_path)?;
    }

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
        let resp = client
            .post(format!("{}/api/v1/devices", agent_config.server_url))
            .bearer_auth(&agent_config.auth_token)
            .json(&serde_json::json!({
                "name": device_name,
                "device_type": detect_device_type(),
                "os": std::env::consts::OS,
                "os_version": "",
                "agent_version": env!("CARGO_PKG_VERSION"),
            }))
            .send()
            .await?;

        if resp.status().is_success() {
            let body: serde_json::Value = resp.json().await?;
            tracing::info!(device_id = %body["id"], "Device registered successfully");
        } else {
            tracing::error!(status = %resp.status(), "Registration failed");
        }
        return Ok(());
    }

    if cli.status {
        print_status(&agent_config, &local_db)?;
        return Ok(());
    }

    // Start daemon mode
    tracing::info!("Starting in daemon mode (Outbound TLS/WSS node active)");

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

    // Start Outbound Connection Manager loop (TLS/WSS tunnel + host LAN IP discovery + remote commands)
    let cm = connection_manager::ConnectionManager::new(
        agent_config.server_url.clone(),
        agent_config.device_id.clone(),
        agent_config.user_id.clone(),
        agent_config.auth_token.clone(),
        agent_config.data_dir.clone(),
        agent_config.allowed_disks.clone(),
        agent_config.excluded_disks.clone(),
    );
    let cm_handle = tokio::spawn(async move {
        cm.start_outbound_loop().await;
    });

    // Start Direct LAN HTTP Server
    let lan_srv = lan_server::LanServer::new(
        agent_config.device_id.clone(),
        agent_config.auth_token.clone(),
        8080,
    );
    let bound_lan_port = match lan_srv.start().await {
        Ok(port) => port,
        Err(e) => {
            tracing::warn!(error = %e, "Failed to start LAN HTTP server");
            8080
        }
    };

    // Start LAN P2P discovery with the actual bound LAN port
    let discovery = discovery::LanDiscovery::new(agent_config.device_id.clone(), bound_lan_port);
    let discovery_handle = {
        let disc = discovery.clone();
        tokio::spawn(async move {
            if let Err(e) = disc.start().await {
                tracing::warn!(error = %e, "LAN peer discovery disabled or unavailable");
            }
        })
    };

    // Wait for shutdown signal
    tokio::signal::ctrl_c().await?;
    tracing::info!("Shutting down PCOS Agent...");

    watcher_handle.abort();
    sync_handle.abort();
    cm_handle.abort();
    discovery_handle.abort();

    Ok(())
}

fn print_status(config: &config::AgentConfig, db: &db::LocalDb) -> anyhow::Result<()> {
    println!("PCOS Agent v{}", env!("CARGO_PKG_VERSION"));
    println!("Server: {}", config.server_url);
    println!(
        "Device ID: {}",
        if config.device_id.is_empty() {
            "Not Enrolled"
        } else {
            &config.device_id
        }
    );
    println!("Data dir: {}", config.data_dir);
    println!("Sync folders: {}", config.sync_folders.len());
    for folder in &config.sync_folders {
        println!("  - {}", folder);
    }
    if !config.allowed_disks.is_empty() {
        println!("Allowed storage disks: {:?}", config.allowed_disks);
    }
    if !config.excluded_disks.is_empty() {
        println!("Excluded storage disks: {:?}", config.excluded_disks);
    }
    let stats = db.stats()?;
    println!("Cached files: {}", stats.total_files);
    println!("Pending sync: {}", stats.pending_sync);
    Ok(())
}

fn detect_device_type() -> &'static str {
    // Simple heuristic
    if std::env::consts::OS == "android" || std::env::consts::OS == "ios" {
        "phone"
    } else {
        "desktop"
    }
}

fn shellexpand(path: &str) -> String {
    if path.starts_with('~') {
        if let Some(home) = dirs::home_dir() {
            return path.replacen('~', &home.to_string_lossy(), 1);
        }
    }
    path.to_string()
}
