// PCOS Physical Storage Disk Discovery & Advertising
// Enumerates physical hardware volumes, mounts, and measures actual capacity.

use serde::{Deserialize, Serialize};
use sysinfo::Disks;
use tracing::{info, warn};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiskCapabilities {
    pub ffmpeg: bool,
    pub ocr: bool,
    pub tantivy: bool,
    pub ollama: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiscoveredDisk {
    pub volume_uuid: Option<String>,
    pub mount_point: String,
    pub name: String,
    pub fs_type: String,
    pub total_capacity_bytes: u64,
    pub available_capacity_bytes: u64,
    pub capabilities: DiskCapabilities,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AdvertisePayload {
    pub device_id: String,
    pub disks: Vec<DiscoveredDisk>,
}

/// Enumerate physically mounted disks and volumes on this machine, respecting allow/exclude policies.
pub fn discover_physical_disks(
    ffmpeg_available: bool,
    allowed: &[String],
    excluded: &[String],
) -> Vec<DiscoveredDisk> {
    let disks = Disks::new_with_refreshed_list();
    let mut discovered = Vec::new();

    for disk in &disks {
        let mount_point = disk.mount_point().to_string_lossy().to_string();
        let total = disk.total_space();
        let available = disk.available_space();

        // Skip zero-byte virtual mounts (e.g. procfs, devfs, loop devices without storage)
        if total == 0 {
            continue;
        }

        let clean_mount = mount_point.trim().trim_end_matches(['\\', '/']).to_lowercase();

        // Check exclusions (e.g. "C:\\" or "C:" or "C")
        let is_excluded = excluded.iter().any(|ex| {
            let clean_ex = ex.trim().trim_end_matches(['\\', '/']).to_lowercase();
            clean_ex == clean_mount || clean_ex == clean_mount.trim_end_matches(':')
        });
        if is_excluded {
            continue;
        }

        // If allowlist is defined, disk must match allowlist
        if !allowed.is_empty() {
            let is_allowed = allowed.iter().any(|al| {
                let clean_al = al.trim().trim_end_matches(['\\', '/']).to_lowercase();
                clean_al == clean_mount || clean_al == clean_mount.trim_end_matches(':')
            });
            if !is_allowed {
                continue;
            }
        }

        let raw_name = disk.name().to_string_lossy().to_string();
        let fs_type = disk.file_system().to_string_lossy().to_string();

        let display_name = if raw_name.trim().is_empty() {
            format!("Disk ({})", mount_point)
        } else {
            raw_name
        };

        // Stable UUID surrogate based on mount point and name
        let uuid = format!(
            "{:x}",
            sha2::Sha256::digest(format!("{}:{}", display_name, mount_point).as_bytes())
        );

        discovered.push(DiscoveredDisk {
            volume_uuid: Some(uuid[..16].to_string()),
            mount_point,
            name: display_name,
            fs_type: if fs_type.is_empty() { "unknown".into() } else { fs_type },
            total_capacity_bytes: total,
            available_capacity_bytes: available,
            capabilities: DiskCapabilities {
                ffmpeg: ffmpeg_available,
                ocr: false,
                tantivy: false,
                ollama: false,
            },
        });
    }

    // Also support custom directories specified in allowed_disks (e.g. "C:\\Users\\dayan\\PCOS")
    for custom in allowed {
        let custom_path = std::path::Path::new(custom);
        if custom_path.exists() && custom_path.is_dir() {
            let custom_str = custom.trim().to_string();
            let clean_custom = custom_str.trim_end_matches(['\\', '/']).to_lowercase();
            // If not already covered by a root mount point
            if !discovered.iter().any(|d| d.mount_point.trim_end_matches(['\\', '/']).to_lowercase() == clean_custom) {
                let free_gb = get_disk_free_gb(&custom_str);
                let available_bytes = (free_gb * 1024.0 * 1024.0 * 1024.0) as u64;
                let uuid = format!(
                    "{:x}",
                    sha2::Sha256::digest(format!("CustomDir:{}", custom_str).as_bytes())
                );
                discovered.push(DiscoveredDisk {
                    volume_uuid: Some(uuid[..16].to_string()),
                    mount_point: custom_str.clone(),
                    name: format!("Storage Folder ({})", custom_str),
                    fs_type: "directory".into(),
                    total_capacity_bytes: available_bytes,
                    available_capacity_bytes: available_bytes,
                    capabilities: DiskCapabilities {
                        ffmpeg: ffmpeg_available,
                        ocr: false,
                        tantivy: false,
                        ollama: false,
                    },
                });
            }
        }
    }

    discovered
}

/// Get available disk space in GB for a specific path.
pub fn get_disk_free_gb(target_path: &str) -> f64 {
    let disks = Disks::new_with_refreshed_list();
    let target = std::path::Path::new(target_path);

    // Find the disk whose mount point is the longest prefix of target_path
    let mut best_match: Option<&sysinfo::Disk> = None;
    let mut best_len = 0;

    for disk in &disks {
        let mount = disk.mount_point();
        if target.starts_with(mount) {
            let len = mount.as_os_str().len();
            if len >= best_len {
                best_len = len;
                best_match = Some(disk);
            }
        }
    }

    if let Some(disk) = best_match {
        disk.available_space() as f64 / (1024.0 * 1024.0 * 1024.0)
    } else if let Some(first) = disks.first() {
        first.available_space() as f64 / (1024.0 * 1024.0 * 1024.0)
    } else {
        0.0
    }
}

/// Advertise all discovered physical storage nodes to the PCOS control plane.
pub async fn advertise_storage_nodes(
    client: &reqwest::Client,
    server_url: &str,
    auth_token: &str,
    device_id: &str,
    ffmpeg_available: bool,
    allowed: &[String],
    excluded: &[String],
) -> anyhow::Result<Vec<DiscoveredDisk>> {
    let disks = discover_physical_disks(ffmpeg_available, allowed, excluded);
    if disks.is_empty() {
        warn!("No physical disks matched the storage policy on this node.");
        return Ok(disks);
    }

    let payload = AdvertisePayload {
        device_id: device_id.to_string(),
        disks: disks.clone(),
    };

    let url = format!("{}/api/v1/agent/storage/advertise", server_url.trim_end_matches('/'));
    let resp = client
        .post(&url)
        .bearer_auth(auth_token)
        .json(&payload)
        .send()
        .await?;

    if !resp.status().is_success() {
        let status = resp.status();
        let err_text = resp.text().await.unwrap_or_default();
        anyhow::bail!("Storage advertisement failed (status {}): {}", status, err_text);
    }

    info!(
        count = disks.len(),
        "Successfully advertised physical storage disks to control plane"
    );

    Ok(disks)
}

use sha2::Digest;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_discover_physical_disks_finds_host_drives() {
        let disks = discover_physical_disks(false, &[], &[]);
        // On any host running tests, there is at least one mounted volume
        assert!(!disks.is_empty(), "Expected to discover at least one physical disk");
        for d in &disks {
            assert!(d.total_capacity_bytes > 0);
            assert!(!d.mount_point.is_empty());
        }
    }

    #[test]
    fn test_get_disk_free_gb() {
        let free = get_disk_free_gb(".");
        assert!(free >= 0.0);
    }
}
