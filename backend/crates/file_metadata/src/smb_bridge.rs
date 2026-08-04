//! SMB/CIFS bridge module.
//!
//! Exposes PCOS file storage as an SMB share for Windows Explorer, macOS Finder,
//! and Linux file managers. Uses the SMB2 protocol over TCP port 445.
//!
//! This is a protocol stub — full SMB2 implementation requires the `smb2` crate
//! or integration with Samba. The struct and trait definitions below provide
//! the foundation for a production SMB bridge.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// SMB share configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SmbShareConfig {
    pub name: String,
    pub path: String,
    pub user_id: Uuid,
    pub read_only: bool,
    pub guest_access: bool,
    pub max_connections: u32,
}

/// SMB session state.
#[derive(Debug, Clone)]
pub struct SmbSession {
    pub session_id: u64,
    pub user_id: Uuid,
    pub tree_id: u32,
    pub connected_at: std::time::SystemTime,
}

/// SMB bridge service.
pub struct SmbBridge {
    shares: Vec<SmbShareConfig>,
    sessions: std::sync::RwLock<Vec<SmbSession>>,
}

impl SmbBridge {
    pub fn new() -> Self {
        Self {
            shares: Vec::new(),
            sessions: std::sync::RwLock::new(Vec::new()),
        }
    }

    /// Register a share for a user's storage.
    pub fn add_share(&mut self, config: SmbShareConfig) {
        tracing::info!(share = %config.name, user = %config.user_id, "SMB share registered");
        self.shares.push(config);
    }

    /// List active shares.
    pub fn list_shares(&self) -> &[SmbShareConfig] {
        &self.shares
    }

    /// Get active session count.
    pub fn active_sessions(&self) -> usize {
        self.sessions.read().map(|s| s.len()).unwrap_or(0)
    }

    /// Placeholder: Start the SMB listener on port 445.
    /// In production, implement SMB2 NEGOTIATE → SESSION_SETUP → TREE_CONNECT → CREATE/READ/WRITE/CLOSE.
    pub async fn start(&self, _bind: &str) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        tracing::info!("SMB bridge ready (protocol stub — integrate with Samba for production)");
        // Production implementation:
        // 1. Listen on TCP 445
        // 2. Handle SMB2 NEGOTIATE (dialect selection)
        // 3. SESSION_SETUP with NTLMSSP or Kerberos
        // 4. TREE_CONNECT to map shares
        // 5. CREATE/READ/WRITE/CLOSE for file operations
        // 6. Map operations to PCOS file_entries DB + storage
        Ok(())
    }
}

impl Default for SmbBridge {
    fn default() -> Self {
        Self::new()
    }
}
