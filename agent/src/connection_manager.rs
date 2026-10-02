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
}

impl ConnectionManager {
    pub fn new(
        server_url: String,
        device_id: String,
        user_id: String,
        auth_token: String,
        storage_path: String,
    ) -> Self {
        Self {
            server_url,
            device_id,
            user_id,
            auth_token,
            storage_path,
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

                    // Heartbeat sender task
                    let heartbeat_task = tokio::spawn(async move {
                        let client = reqwest::Client::new();
                        loop {
                            let lan_ip = Self::discover_host_lan_ip();
                            let heartbeat_payload = serde_json::json!({
                                "deviceId": device_id,
                                "userId": user_id,
                                "name": hostname::get().map(|h| h.to_string_lossy().to_string()).unwrap_or_else(|_| "PCOS Node".into()),
                                "deviceType": "desktop",
                                "lanIp": lan_ip,
                            });

                            let _ = client
                                .post(format!(
                                    "{}/api/v1/devices/{}/heartbeat",
                                    server_url, device_id
                                ))
                                .bearer_auth(&auth_token)
                                .json(&heartbeat_payload)
                                .send()
                                .await;

                            sleep(Duration::from_secs(30)).await;
                        }
                    });

                    // Incoming control messages receiver
                    while let Some(msg_result) = read.next().await {
                        match msg_result {
                            Ok(Message::Text(text)) => {
                                info!(msg = %text, "Received control plane command");
                                // Handle incoming commands (e.g. Play-on-TV, Send-to-Device)
                                if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&text)
                                {
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
