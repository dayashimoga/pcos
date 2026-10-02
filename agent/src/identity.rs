// Stable PCOS Logical Identity Model
// Devices, storage nodes, and files are identified by cryptographic logical IDs, never raw IP addresses.

use serde::{Deserialize, Serialize};
use std::fmt;
use std::str::FromStr;
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct PcosUri {
    pub cloud_id: String,
    pub device_id: Uuid,
    pub node_id: Option<Uuid>,
    pub file_id: Option<Uuid>,
}

impl fmt::Display for PcosUri {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "pcos://cloud/{}/device/{}", self.cloud_id, self.device_id)?;
        if let Some(node) = self.node_id {
            write!(f, "/node/{}", node)?;
        }
        if let Some(file) = self.file_id {
            write!(f, "/file/{}", file)?;
        }
        Ok(())
    }
}

impl FromStr for PcosUri {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let trimmed = s.trim();
        if !trimmed.starts_with("pcos://cloud/") {
            anyhow::bail!("Invalid PCOS URI format: must start with pcos://cloud/");
        }

        let rest = &trimmed["pcos://cloud/".len()..];
        let parts: Vec<&str> = rest.split('/').collect();

        if parts.len() < 3 || parts[1] != "device" {
            anyhow::bail!("Invalid PCOS URI format: expected pcos://cloud/<cloud_id>/device/<device_id>");
        }

        let cloud_id = parts[0].to_string();
        let device_id = Uuid::parse_str(parts[2])?;

        let mut node_id = None;
        let mut file_id = None;

        let mut i = 3;
        while i < parts.len() {
            if parts[i] == "node" && i + 1 < parts.len() {
                node_id = Some(Uuid::parse_str(parts[i + 1])?);
                i += 2;
            } else if parts[i] == "file" && i + 1 < parts.len() {
                file_id = Some(Uuid::parse_str(parts[i + 1])?);
                i += 2;
            } else {
                i += 1;
            }
        }

        Ok(PcosUri {
            cloud_id,
            device_id,
            node_id,
            file_id,
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeIdentity {
    pub user_id: Uuid,
    pub cloud_id: String,
    pub device_id: Uuid,
    pub storage_node_id: Uuid,
    pub device_name: String,
    pub device_type: String, // desktop, laptop, nas, server
}

impl NodeIdentity {
    pub fn new(cloud_id: String, user_id: Uuid, device_name: String) -> Self {
        Self {
            user_id,
            cloud_id,
            device_id: Uuid::new_v4(),
            storage_node_id: Uuid::new_v4(),
            device_name,
            device_type: detect_platform_device_type().to_string(),
        }
    }

    pub fn to_uri(&self) -> PcosUri {
        PcosUri {
            cloud_id: self.cloud_id.clone(),
            device_id: self.device_id,
            node_id: Some(self.storage_node_id),
            file_id: None,
        }
    }
}

pub fn detect_platform_device_type() -> &'static str {
    #[cfg(target_os = "android")]
    return "phone";
    #[cfg(target_os = "ios")]
    return "phone";
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    return "desktop";
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pcos_uri_roundtrip() {
        let dev_id = Uuid::new_v4();
        let node_id = Uuid::new_v4();
        let file_id = Uuid::new_v4();

        let uri = PcosUri {
            cloud_id: "cld_alice123".into(),
            device_id: dev_id,
            node_id: Some(node_id),
            file_id: Some(file_id),
        };

        let formatted = uri.to_string();
        assert!(formatted.starts_with("pcos://cloud/cld_alice123/device/"));

        let parsed: PcosUri = formatted.parse().unwrap();
        assert_eq!(parsed.cloud_id, "cld_alice123");
        assert_eq!(parsed.device_id, dev_id);
        assert_eq!(parsed.node_id, Some(node_id));
        assert_eq!(parsed.file_id, Some(file_id));
    }
}
