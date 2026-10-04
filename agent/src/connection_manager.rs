// PCOS Outbound-Only Node Connection Manager
// Maintains outbound TLS/WSS connection to the Control Plane without requiring inbound ports.
// Coordinates Direct LAN, P2P WireGuard, and Relay fallbacks.

use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use std::net::UdpSocket;
use std::time::Duration;
use tokio::time::sleep;
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::protocol::Message;
use tracing::{error, info, warn};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RouteResolution {
    pub is_online: bool,
    pub recommended_route: String, // "LAN", "P2P", "Relay", "Offline"
    pub lan_ip: Option<String>,
    pub public_ip: Option<String>,
    pub wireguard_pubkey: Option<String>,
    pub relay_endpoint: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ConnectionManager {
    server_url: String,
    device_id: String,
    user_id: String,
    auth_token: String,
    storage_path: String,
    allowed_disks: Vec<String>,
    excluded_disks: Vec<String>,
}

impl ConnectionManager {
    pub fn new(
        server_url: String,
        device_id: String,
        user_id: String,
        auth_token: String,
        storage_path: String,
        allowed_disks: Vec<String>,
        excluded_disks: Vec<String>,
    ) -> Self {
        Self {
            server_url,
            device_id,
            user_id,
            auth_token,
            storage_path,
            allowed_disks,
            excluded_disks,
        }
    }

    /// Discover real host LAN IP by probing outward routing.
    pub fn discover_host_lan_ip() -> String {
        // UDP connect to a public DNS IP does not send packets, but causes OS kernel
        // to assign the local network interface IP that routes to the LAN/Internet.
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
    }

    /// Resolve safest and fastest available route to a peer storage node.
    pub async fn resolve_route(&self, peer_device_id: &str) -> anyhow::Result<RouteResolution> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()?;

        let lan_ip = Self::discover_host_lan_ip();
        let url = format!(
            "{}/api/v1/devices/resolve/{}?callerLanIp={}",
            self.server_url, peer_device_id, lan_ip
        );

        let resp = client
            .get(&url)
            .bearer_auth(&self.auth_token)
            .send()
            .await?;

        if !resp.status().is_success() {
            anyhow::bail!("Route resolution failed with status: {}", resp.status());
        }

        let resolution: RouteResolution = resp.json().await?;

        // If recommended route is LAN, perform active low-latency ping probe (<20ms)
        if resolution.recommended_route == "LAN" {
            if let Some(target_ip) = &resolution.lan_ip {
                let ping_url = format!("http://{}:8080/health", target_ip);
                let start = std::time::Instant::now();
                if let Ok(ping_resp) = client
                    .get(&ping_url)
                    .timeout(Duration::from_millis(150))
                    .send()
                    .await
                {
                    if ping_resp.status().is_success() {
                        let latency = start.elapsed();
                        info!(peer = %peer_device_id, ip = %target_ip, latency_ms = latency.as_millis(), "Direct LAN route confirmed optimal");
                        return Ok(resolution);
                    }
                }
                warn!(target_ip = %target_ip, "LAN probe timed out, falling back to P2P/Relay");
            }
        }

        Ok(resolution)
    }

    /// Long-running outbound control loop: connects WSS to Control Plane and processes commands.
    pub async fn start_outbound_loop(&self) {
        loop {
            let ws_url = if self.server_url.starts_with("https://") {
                self.server_url.replace("https://", "wss://")
            } else {
                self.server_url.replace("http://", "ws://")
            };

            let connect_endpoint = format!("{}/ws/presence?deviceId={}", ws_url, self.device_id);
            info!(endpoint = %connect_endpoint, "Establishing outbound TLS/WSS tunnel to Control Plane...");

            match connect_async(&connect_endpoint).await {
                Ok((ws_stream, _)) => {
                    info!("Outbound control tunnel connected! Storage node is live and ready.");
                    let (mut write, mut read) = ws_stream.split();

                    let device_id = self.device_id.clone();
                    let user_id = self.user_id.clone();
                    let server_url = self.server_url.clone();
                    let auth_token = self.auth_token.clone();
                    let allowed_disks = self.allowed_disks.clone();
                    let excluded_disks = self.excluded_disks.clone();

                    // Physical storage advertisement & heartbeat sender task
                    let heartbeat_task = tokio::spawn(async move {
                        let client = reqwest::Client::new();
                        let mut loop_count: usize = 0;

                        loop {
                            // Discover and advertise physical disks on initial connect and periodically (~5 mins)
                            if loop_count % 10 == 0 {
                                let (ffmpeg_ok, _) = crate::doctor::check_ffmpeg();
                                if let Err(e) = crate::disks::advertise_storage_nodes(
                                    &client,
                                    &server_url,
                                    &auth_token,
                                    &device_id,
                                    ffmpeg_ok,
                                    &allowed_disks,
                                    &excluded_disks,
                                )
                                .await
                                {
                                    warn!(error = %e, "Physical storage node advertisement failed");
                                }
                            }
                            loop_count = loop_count.wrapping_add(1);

                            let lan_ip = Self::discover_host_lan_ip();
                            let heartbeat_payload = serde_json::json!({
                                "deviceId": device_id,
                                "userId": user_id,
                                "name": hostname::get().map(|h| h.to_string_lossy().to_string()).unwrap_or_else(|_| "PCOS Node".into()),
                                "deviceType": "desktop",
                                "lanIp": lan_ip,
                            });

                            let res = client
                                .post(format!(
                                    "{}/api/v1/devices/{}/heartbeat",
                                    server_url, device_id
                                ))
                                .bearer_auth(&auth_token)
                                .json(&heartbeat_payload)
                                .send()
                                .await;

                            if let Err(e) = res {
                                warn!(error = %e, "Agent heartbeat failed to deliver to control plane");
                            }

                            sleep(Duration::from_secs(30)).await;
                        }
                    });

                    let storage_root = self.storage_path.clone();
                    let allowed_policy = self.allowed_disks.clone();
                    let excluded_policy = self.excluded_disks.clone();

                    // Incoming control messages receiver
                    while let Some(msg_result) = read.next().await {
                        match msg_result {
                            Ok(Message::Text(text)) => {
                                info!(msg = %text, "Received control plane command");
                                if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&text) {
                                    // 1. Filesystem Data Plane Operations
                                    if parsed.get("op").is_some() {
                                        let resp = handle_fs_command(
                                            std::path::Path::new(&storage_root),
                                            &parsed,
                                            &allowed_policy,
                                            &excluded_policy,
                                        ).await;
                                        let resp_json = resp.to_string();
                                        if let Err(e) = write.send(Message::Text(resp_json)).await {
                                            error!(error = %e, "Failed to send filesystem response over WSS tunnel");
                                        }
                                    } else {
                                        // 2. Remote control plane commands (e.g. Play-on-TV, Send-to-Device)
                                        let command = parsed["command"].as_str().unwrap_or("");
                                        match command {
                                            "play_on_tv" => {
                                                info!(payload = ?parsed["payload"], "Play-on-TV command received — initiating stream");
                                            }
                                            "send_to_device" => {
                                                info!(payload = ?parsed["payload"], "Send-to-Device payload received");
                                            }
                                            _ => {}
                                        }
                                    }
                                }
                            }
                            Ok(Message::Ping(payload)) => {
                                let _ = write.send(Message::Pong(payload)).await;
                            }
                            Ok(Message::Close(_)) => {
                                warn!("Control tunnel closed by remote edge broker");
                                break;
                            }
                            Err(e) => {
                                error!(error = %e, "Control tunnel socket error");
                                break;
                            }
                            _ => {}
                        }
                    }

                    heartbeat_task.abort();
                }
                Err(e) => {
                    warn!(error = %e, "Control tunnel connection failed. Retrying in 5 seconds...");
                }
            }

            sleep(Duration::from_secs(5)).await;
        }
    }
}

/// Handle filesystem operations requested by remote clients through the control plane tunnel
async fn handle_fs_command(
    default_root: &std::path::Path,
    req: &serde_json::Value,
    allowed: &[String],
    excluded: &[String],
) -> serde_json::Value {
    let request_id = req["request_id"].as_str().unwrap_or("").to_string();
    let op = req["op"].as_str().unwrap_or("");
    let rel_path = req["relative_path"].as_str().unwrap_or("");

    // Determine target root
    let root = if let Some(custom_root) = req["storage_path"].as_str() {
        if !custom_root.trim().is_empty() {
            std::path::Path::new(custom_root)
        } else {
            default_root
        }
    } else {
        default_root
    };

    // Enforce node disk policy
    let root_str = root.to_string_lossy().to_string();
    let clean_root = root_str.trim().trim_end_matches(['\\', '/']).to_lowercase();

    let is_forbidden = if !allowed.is_empty() {
        !allowed.iter().any(|al| {
            let clean_al = al.trim().trim_end_matches(['\\', '/']).to_lowercase();
            clean_root == clean_al || clean_root.starts_with(&clean_al) || clean_al.starts_with(&clean_root)
        })
    } else {
        excluded.iter().any(|ex| {
            let clean_ex = ex.trim().trim_end_matches(['\\', '/']).to_lowercase();
            clean_root == clean_ex || clean_root.starts_with(&clean_ex)
        })
    };

    if is_forbidden {
        return serde_json::json!({
            "type": "fs_response",
            "request_id": request_id,
            "success": false,
            "error": format!("Access to storage path '{}' is restricted by node policy in agent.toml", root.display())
        });
    }

    match op {
        "fs_list_dir" => {
            match crate::fs_handler::FsHandler::list_dir(root, rel_path) {
                Ok(result) => serde_json::json!({
                    "type": "fs_response",
                    "request_id": request_id,
                    "success": true,
                    "result": result
                }),
                Err(e) => serde_json::json!({
                    "type": "fs_response",
                    "request_id": request_id,
                    "success": false,
                    "error": e.to_string()
                }),
            }
        }
        "fs_stat" => {
            match crate::fs_handler::FsHandler::stat(root, rel_path) {
                Ok(result) => serde_json::json!({
                    "type": "fs_response",
                    "request_id": request_id,
                    "success": true,
                    "result": result
                }),
                Err(e) => serde_json::json!({
                    "type": "fs_response",
                    "request_id": request_id,
                    "success": false,
                    "error": e.to_string()
                }),
            }
        }
        "fs_read_chunk" => {
            let offset = req["offset"].as_u64().unwrap_or(0);
            let length = req["length"].as_u64().unwrap_or(256 * 1024) as usize;
            match crate::fs_handler::FsHandler::read_chunk(root, rel_path, offset, length) {
                Ok(result) => serde_json::json!({
                    "type": "fs_response",
                    "request_id": request_id,
                    "success": true,
                    "result": result
                }),
                Err(e) => serde_json::json!({
                    "type": "fs_response",
                    "request_id": request_id,
                    "success": false,
                    "error": e.to_string()
                }),
            }
        }
        "fs_write_chunk" => {
            let offset = req["offset"].as_u64().unwrap_or(0);
            let b64 = req["data_base64"].as_str().unwrap_or("");
            match crate::fs_handler::base64_decode(b64) {
                Ok(bytes) => {
                    match crate::fs_handler::FsHandler::write_chunk(root, rel_path, offset, &bytes) {
                        Ok(result) => serde_json::json!({
                            "type": "fs_response",
                            "request_id": request_id,
                            "success": true,
                            "result": result
                        }),
                        Err(e) => serde_json::json!({
                            "type": "fs_response",
                            "request_id": request_id,
                            "success": false,
                            "error": e.to_string()
                        }),
                    }
                }
                Err(err) => serde_json::json!({
                    "type": "fs_response",
                    "request_id": request_id,
                    "success": false,
                    "error": format!("Base64 decode error: {}", err)
                }),
            }
        }
        "fs_delete" => {
            let recursive = req["recursive"].as_bool().unwrap_or(false);
            match crate::fs_handler::FsHandler::delete(root, rel_path, recursive) {
                Ok(deleted) => serde_json::json!({
                    "type": "fs_response",
                    "request_id": request_id,
                    "success": true,
                    "result": { "deleted": deleted }
                }),
                Err(e) => serde_json::json!({
                    "type": "fs_response",
                    "request_id": request_id,
                    "success": false,
                    "error": e.to_string()
                }),
            }
        }
        "fs_mkdir" => {
            match crate::fs_handler::FsHandler::mkdir(root, rel_path) {
                Ok(created) => serde_json::json!({
                    "type": "fs_response",
                    "request_id": request_id,
                    "success": true,
                    "result": { "created": created }
                }),
                Err(e) => serde_json::json!({
                    "type": "fs_response",
                    "request_id": request_id,
                    "success": false,
                    "error": e.to_string()
                }),
            }
        }
        "media_probe" => {
            let canonical_root = match root.canonicalize() {
                Ok(p) => p,
                Err(e) => return serde_json::json!({
                    "type": "fs_response",
                    "request_id": request_id,
                    "success": false,
                    "error": format!("Invalid root: {}", e)
                }),
            };
            let target_path = match crate::fs_handler::FsHandler::safe_resolve(&canonical_root, rel_path) {
                Ok(p) => p,
                Err(e) => return serde_json::json!({
                    "type": "fs_response",
                    "request_id": request_id,
                    "success": false,
                    "error": e.to_string()
                }),
            };
            match crate::transcoder::Transcoder::probe(&target_path).await {
                Ok(probe_result) => serde_json::json!({
                    "type": "fs_response",
                    "request_id": request_id,
                    "success": true,
                    "result": probe_result
                }),
                Err(e) => serde_json::json!({
                    "type": "fs_response",
                    "request_id": request_id,
                    "success": false,
                    "error": e
                }),
            }
        }
        _ => serde_json::json!({
            "type": "fs_response",
            "request_id": request_id,
            "success": false,
            "error": format!("Unknown filesystem operation: '{}'", op)
        }),
    }
}
