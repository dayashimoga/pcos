use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentConfig {
    pub server_url: String,
    pub auth_token: String,
    pub device_id: String,
    pub data_dir: String,
    pub sync_folders: Vec<String>,
    pub sync_interval_secs: u64,
    pub ignore_patterns: Vec<String>,
}

impl Default for AgentConfig {
    fn default() -> Self {
        let data_dir = dirs::data_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("pcos-agent")
            .to_string_lossy()
            .to_string();

        Self {
            server_url: "http://localhost:8080".to_string(),
            auth_token: String::new(),
            device_id: String::new(),
            data_dir,
            sync_folders: vec![],
            sync_interval_secs: 30,
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
            let config: Self = toml::from_str(&content)?;
            return Ok(config);
        }

        // Create default config
        let config = Self::default();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let content = toml::to_string_pretty(&config)?;
        std::fs::write(&path, content)?;

        tracing::info!(path = %path.display(), "Created default config file — please edit it with your server URL and auth token");
        Ok(config)
    }
}
