use axum::{extract::State, Json};
use pcos_common::AppState;
use serde::{Deserialize, Serialize};
use std::net::UdpSocket;

#[derive(Debug, Serialize, Deserialize)]
pub struct ConnectivityDiagnostics {
    pub lan_ip: String,
    pub hostname: String,
    pub is_private_ip: bool,
    pub is_cgnat: bool,
    pub tls_enabled: bool,
    pub active_connect_mode: String,
    pub recommended_provider: String,
    pub available_providers: Vec<String>,
    pub ports: PortStatus,
    pub storage_healthy: bool,
    pub database_healthy: bool,
    pub recommendations: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PortStatus {
    pub http_port: u16,
    pub https_port: u16,
    pub wireguard_port: u16,
}

pub async fn get_connectivity_diagnostics(
    State(state): State<AppState>,
) -> Json<ConnectivityDiagnostics> {
    // 1. Determine local LAN IP (prioritize PCOS_LAN_IP env var if passed, else UDP routing)
    let env_lan_ip = std::env::var("PCOS_LAN_IP")
        .or_else(|_| std::env::var("PCOS_SERVER_IP"))
        .ok()
        .filter(|s| !s.trim().is_empty());

    let lan_ip = if let Some(ip) = env_lan_ip {
        let clean = ip.trim()
            .trim_start_matches("http://")
            .trim_start_matches("https://");
        let host = clean.split('/').next().unwrap_or(clean);
        host.split(':').next().unwrap_or(host).to_string()
    } else {
        match UdpSocket::bind("0.0.0.0:0") {
            Ok(socket) => match socket.connect("1.1.1.1:80") {
                Ok(_) => match socket.local_addr() {
                    Ok(addr) => addr.ip().to_string(),
                    Err(_) => "127.0.0.1".to_string(),
                },
                Err(_) => "127.0.0.1".to_string(),
            },
            Err(_) => "127.0.0.1".to_string(),
        }
    };

    // 2. Check RFC1918 and RFC6598 (CGNAT 100.64.0.0/10)
    let is_private = is_private_ip_str(&lan_ip);
    let is_cgnat = is_cgnat_ip_str(&lan_ip)
        || std::env::var("PCOS_CGNAT")
            .map(|v| v == "true" || v == "1")
            .unwrap_or(false);

    // 3. Hostname
    let hostname = std::env::var("HOSTNAME")
        .or_else(|_| std::env::var("COMPUTERNAME"))
        .unwrap_or_else(|_| "pcos-server".to_string());

    // 4. TLS status
    let tls_enabled = std::env::var("PCOS_TLS_ENABLED")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(false)
        || std::env::var("PCOS_DOMAIN").is_ok();

    // 5. Connect mode
    let active_connect_mode =
        std::env::var("PCOS_CONNECT_MODE").unwrap_or_else(|_| "automatic".to_string());

    // 6. Recommended remote access provider
    let mut recommendations = Vec::new();
    let recommended_provider = if active_connect_mode == "lan_only" {
        recommendations.push("Configured for LAN only. Remote access disabled.".to_string());
        "LAN Only".to_string()
    } else if is_cgnat {
        recommendations.push(
            "Carrier-Grade NAT (CGNAT) detected: Inbound ports are likely filtered by ISP."
                .to_string(),
        );
        recommendations.push(
            "PCOS recommends WireGuard P2P (Headscale/NetBird) or Encrypted Relay Tunnel."
                .to_string(),
        );
        "WireGuard / Headscale P2P".to_string()
    } else if tls_enabled {
        recommendations.push(
            "TLS domain configured: Direct HTTPS access is optimal for all remote clients."
                .to_string(),
        );
        "Direct HTTPS".to_string()
    } else {
        recommendations.push("Zero-config automatic mode: Using Direct LAN when at home, WireGuard/Relay when remote.".to_string());
        "Automatic (Direct LAN + WireGuard Failover)".to_string()
    };

    let available_providers = vec![
        "Direct LAN".to_string(),
        "Direct HTTPS".to_string(),
        "WireGuard / Headscale P2P".to_string(),
        "NetBird Mesh".to_string(),
        "Encrypted Relay Tunnel".to_string(),
    ];

    // 7. Check database connectivity
    let database_healthy = sqlx::query("SELECT 1")
        .execute(state.db.pool())
        .await
        .is_ok();

    // 8. Check storage writeability
    let storage_path = std::path::Path::new(&state.config.storage.base_path);
    let storage_healthy = storage_path.exists()
        && match tokio::fs::metadata(storage_path).await {
            Ok(m) => !m.permissions().readonly(),
            Err(_) => false,
        };

    Json(ConnectivityDiagnostics {
        lan_ip,
        hostname,
        is_private_ip: is_private,
        is_cgnat,
        tls_enabled,
        active_connect_mode,
        recommended_provider,
        available_providers,
        ports: PortStatus {
            http_port: 80,
            https_port: 443,
            wireguard_port: 51820,
        },
        storage_healthy,
        database_healthy,
        recommendations,
    })
}

fn is_private_ip_str(ip: &str) -> bool {
    if let Ok(std::net::IpAddr::V4(ipv4)) = ip.parse::<std::net::IpAddr>() {
        ipv4.is_private() || ipv4.is_loopback()
    } else {
        false
    }
}

fn is_cgnat_ip_str(ip: &str) -> bool {
    if let Ok(std::net::IpAddr::V4(ipv4)) = ip.parse::<std::net::IpAddr>() {
        let octets = ipv4.octets();
        // 100.64.0.0/10 -> 100.64.0.0 to 100.127.255.255
        octets[0] == 100 && (octets[1] >= 64 && octets[1] <= 127)
    } else {
        false
    }
}
