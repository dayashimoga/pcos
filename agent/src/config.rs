use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct AgentConfig {
    pub server_url: String,
    pub auth_token: String,
    pub device_id: String,
    pub user_id: String,
    pub cloud_id: String,
    pub storage_node_id: String,
    pub data_dir: String,
    pub sync_folders: Vec<String>,
    pub sync_interval_secs: u64,
    pub ignore_patterns: Vec<String>,
    #[serde(default)]
    pub allowed_disks: Vec<String>,
    #[serde(default)]
    pub excluded_disks: Vec<String>,
}

impl Default for AgentConfig {
    fn default() -> Self {
        let data_dir = dirs::data_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("pcos-agent")
            .to_string_lossy()
            .to_string();

        let server_url = std::env::var("PCOS_SERVER_URL")
            .unwrap_or_else(|_| "https://pcos-control-plane.dayashimoga.workers.dev".to_string());

        Self {
            server_url,
            auth_token: String::new(),
            device_id: String::new(),
            user_id: String::new(),
            cloud_id: String::new(),
            storage_node_id: String::new(),
            data_dir,
            sync_folders: vec![],
            sync_interval_secs: 30,
            allowed_disks: vec![],
            excluded_disks: vec![],
            ignore_patterns: vec![
                "*.tmp".to_string(),
                "*.swp".to_string(),
                ".git/**".to_string(),
                "node_modules/**".to_string(),
                "target/**".to_string(),
                ".DS_Store".to_string(),
                "Thumbs.db".to_string(),
            ],
        }
    }
}

impl AgentConfig {
    pub fn load_or_create(path: &str) -> anyhow::Result<Self> {
        let path = PathBuf::from(path);

        if path.exists() {
            let content = std::fs::read_to_string(&path)?;
            let is_json = path.extension().map_or(false, |ext| ext == "json");
            if is_json {
                let config: Self = serde_json::from_str(&content)?;
                return Ok(config);
            }

            match toml::from_str::<Self>(&content) {
                Ok(config) => return Ok(config),
                Err(toml_err) => {
                    if let Ok(config) = serde_json::from_str::<Self>(&content) {
                        return Ok(config);
                    }
                    return Err(anyhow::anyhow!(
                        "Failed to parse config file as TOML ({}) or JSON",
                        toml_err
                    ));
                }
            }
        }

        // Create default config
        let config = Self::default();
        config.save(path.to_str().unwrap_or("agent.toml"))?;

        tracing::info!(path = %path.display(), "Created default config file");
        Ok(config)
    }

    pub fn save(&self, path: &str) -> anyhow::Result<()> {
        let path = PathBuf::from(path);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let is_json = path.extension().map_or(false, |ext| ext == "json");
        let content = if is_json {
            serde_json::to_string_pretty(self)?
        } else {
            toml::to_string_pretty(self)?
        };
        std::fs::write(&path, content)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_partial_json_deserialization() {
        let json_data = r#"{"server_url": "https://custom.pcos.io", "sync_folders": ["/data"]}"#;
        let config: AgentConfig =
            serde_json::from_str(json_data).expect("Should deserialize partial JSON");
        assert_eq!(config.server_url, "https://custom.pcos.io");
        assert_eq!(config.sync_folders, vec!["/data"]);
        assert_eq!(config.sync_interval_secs, 30);
    }

    #[test]
    fn test_partial_toml_deserialization() {
        let toml_data = r#"
            server_url = "https://custom.pcos.io"
            sync_folders = ["D:\\PCOS"]
        "#;
        let config: AgentConfig =
            toml::from_str(toml_data).expect("Should deserialize partial TOML");
        assert_eq!(config.server_url, "https://custom.pcos.io");
        assert_eq!(config.sync_folders, vec!["D:\\PCOS"]);
        assert_eq!(config.sync_interval_secs, 30);
    }
}
