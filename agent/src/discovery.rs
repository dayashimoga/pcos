//! LAN/P2P discovery module — find other PCOS agents on the local network using mDNS.
//!
//! Broadcasts `_pcos._tcp.local` service and discovers peers for direct LAN sync.

use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::{Arc, RwLock};
use std::time::Duration;

/// Discovered peer on the local network.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Peer {
    pub id: String,
    pub hostname: String,
    pub ip: IpAddr,
    pub port: u16,
    pub last_seen: std::time::SystemTime,
}

/// LAN discovery service using UDP broadcast (simplified mDNS-like).
#[derive(Clone)]
pub struct LanDiscovery {
    peers: Arc<RwLock<HashMap<String, Peer>>>,
    service_port: u16,
    device_id: String,
}

const DISCOVERY_PORT: u16 = 5353;
const BROADCAST_INTERVAL: Duration = Duration::from_secs(30);
const PEER_TIMEOUT: Duration = Duration::from_secs(120);
const MAGIC: &[u8] = b"PCOS-DISCOVER-V1";

impl LanDiscovery {
    pub fn new(device_id: String, service_port: u16) -> Self {
        Self {
            peers: Arc::new(RwLock::new(HashMap::new())),
            service_port,
            device_id,
        }
    }

    /// Get currently discovered peers.
    pub fn peers(&self) -> Vec<Peer> {
        let map = self.peers.read().unwrap();
        let now = std::time::SystemTime::now();
        map.values()
            .filter(|p| now.duration_since(p.last_seen).unwrap_or_default() < PEER_TIMEOUT)
            .cloned()
            .collect()
    }

    /// Start broadcasting and listening for peers.
    pub async fn start(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let socket = match tokio::net::UdpSocket::bind(format!("0.0.0.0:{}", DISCOVERY_PORT)).await {
            Ok(s) => s,
            Err(_) => tokio::net::UdpSocket::bind("0.0.0.0:0").await?,
        };
        socket.set_broadcast(true)?;

        let hostname = hostname::get()
            .map(|h| h.to_string_lossy().to_string())
            .unwrap_or_else(|_| "unknown".to_string());

        // Spawn broadcaster
        let device_id = self.device_id.clone();
        let port = self.service_port;
        let sock = Arc::new(socket);
        let sock_tx = sock.clone();

        tokio::spawn(async move {
            let mut interval = tokio::time::interval(BROADCAST_INTERVAL);
            loop {
                interval.tick().await;
                let msg = format!("{}|{}|{}|{}", 
                    String::from_utf8_lossy(MAGIC), device_id, hostname, port);
                let _ = sock_tx.send_to(msg.as_bytes(), format!("255.255.255.255:{}", DISCOVERY_PORT)).await;
            }
        });

        // Spawn listener
        let peers = self.peers.clone();
        let my_id = self.device_id.clone();
        tokio::spawn(async move {
            let mut buf = [0u8; 512];
            loop {
                match sock.recv_from(&mut buf).await {
                    Ok((len, addr)) => {
                        let msg = String::from_utf8_lossy(&buf[..len]);
                        let parts: Vec<&str> = msg.split('|').collect();
                        if parts.len() == 4 && parts[0] == String::from_utf8_lossy(MAGIC) {
                            let peer_id = parts[1].to_string();
                            if peer_id == my_id { continue; } // Skip self
                            let peer = Peer {
                                id: peer_id.clone(),
                                hostname: parts[2].to_string(),
                                ip: addr.ip(),
                                port: parts[3].parse().unwrap_or(8080),
                                last_seen: std::time::SystemTime::now(),
                            };
                            peers.write().unwrap().insert(peer_id, peer);
                        }
                    }
                    Err(e) => {
                        tracing::warn!(error = %e, "LAN discovery recv error");
                        tokio::time::sleep(Duration::from_secs(5)).await;
                    }
                }
            }
        });

        tracing::info!(device_id = %self.device_id, "LAN discovery started on port {}", DISCOVERY_PORT);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_peer_list_initially_empty() {
        let disc = LanDiscovery::new("test-device".to_string(), 8080);
        assert!(disc.peers().is_empty());
    }

    #[test]
    fn test_peer_tracking() {
        let disc = LanDiscovery::new("test-device".to_string(), 8080);
        {
            let mut map = disc.peers.write().unwrap();
            map.insert("peer-1".to_string(), Peer {
                id: "peer-1".to_string(),
                hostname: "laptop".to_string(),
                ip: "192.168.1.100".parse().unwrap(),
                port: 8080,
                last_seen: std::time::SystemTime::now(),
            });
        }
        assert_eq!(disc.peers().len(), 1);
        assert_eq!(disc.peers()[0].hostname, "laptop");
    }
}
