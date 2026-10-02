// One-Command PCOS Node Setup & Enrollment
// CLI pairing: normal users never need to edit YAML, .env, or configure ports.

use crate::config::AgentConfig;
use std::time::Duration;
use tokio::time::sleep;
use uuid::Uuid;

pub async fn enroll_node_with_code(
    code: &str,
    server_url: &str,
    config_path: &str,
) -> anyhow::Result<()> {
    let clean_code = code.trim().replace(' ', "");
    let base_url = server_url.trim_end_matches('/');

    println!();
    println!("Connecting to PCOS Control Plane at {}...", base_url);

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()?;

    let hostname = hostname::get()
        .map(|h| h.to_string_lossy().to_string())
        .unwrap_or_else(|_| "PCOS Storage Node".into());

    let payload = serde_json::json!({
        "pairing_code": clean_code,
        "device_name": hostname,
        "device_type": "desktop",
        "os": std::env::consts::OS,
        "os_version": "",
        "agent_version": env!("CARGO_PKG_VERSION"),
    });

    // 1. Claim pairing session
    let claim_url = format!("{}/api/v1/devices/pair/claim", base_url);
    let claim_resp = client.post(&claim_url).json(&payload).send().await;

    let mut access_token: Option<String> = None;
    let mut _refresh_token: Option<String> = None;
    let mut device_id: Option<String> = None;

    if let Ok(resp) = claim_resp {
        if resp.status().is_success() {
            let body: serde_json::Value = resp.json().await?;
            if let Some(res) = body.get("redeem_result") {
                access_token = res["access_token"].as_str().map(|s| s.to_string());
                _refresh_token = res["refresh_token"].as_str().map(|s| s.to_string());
                device_id = res["device"]["id"].as_str().map(|s| s.to_string());
            }
        }
    }

    // 2. If waiting for Web approval, poll status
    if access_token.is_none() {
        println!("Pairing request submitted! Please click [Approve] on your PCOS Web or Desktop screen...");
        let status_url = format!(
            "{}/api/v1/devices/pair/status?code={}",
            base_url, clean_code
        );

        for _ in 0..60 {
            sleep(Duration::from_secs(2)).await;
            if let Ok(resp) = client.get(&status_url).send().await {
                if resp.status().is_success() {
                    let body: serde_json::Value = resp.json().await?;
                    let status = body["status"].as_str().unwrap_or("");
                    if status == "approved" {
                        println!("Connection APPROVED by user!");
                        // Redeem tokens
                        let redeem_url = format!("{}/api/v1/devices/pair/redeem", base_url);
                        let redeem_resp = client.post(&redeem_url).json(&payload).send().await?;
                        if redeem_resp.status().is_success() {
                            let r_body: serde_json::Value = redeem_resp.json().await?;
                            access_token = r_body["access_token"].as_str().map(|s| s.to_string());
                            _refresh_token =
                                r_body["refresh_token"].as_str().map(|s| s.to_string());
                            device_id = r_body["device"]["id"].as_str().map(|s| s.to_string());
                            break;
                        }
                    } else if status == "rejected" {
                        anyhow::bail!("Pairing request was declined on your computer screen.");
                    }
                }
            }
        }
    }

    let token = match access_token {
        Some(t) => t,
        None => {
            // Direct redeem fallback
            let redeem_url = format!("{}/api/v1/devices/pair/redeem", base_url);
            let resp = client.post(&redeem_url).json(&payload).send().await?;
            if !resp.status().is_success() {
                anyhow::bail!("Pairing failed: HTTP {}", resp.status());
            }
            let body: serde_json::Value = resp.json().await?;
            device_id = body["device"]["id"].as_str().map(|s| s.to_string());
            body["access_token"].as_str().unwrap().to_string()
        }
    };

    let dev_id = device_id.unwrap_or_else(|| Uuid::new_v4().to_string());

    // 3. Save configuration
    let mut config = AgentConfig::load_or_create(config_path)?;
    config.server_url = base_url.to_string();
    config.auth_token = token;
    config.device_id = dev_id.clone();

    // Default sync folder in user home
    let default_sync = dirs::home_dir()
        .map(|h| h.join("PCOS").to_string_lossy().to_string())
        .unwrap_or_else(|| "pcos_storage".into());

    let _ = std::fs::create_dir_all(&default_sync);
    if !config.sync_folders.contains(&default_sync) {
        config.sync_folders.push(default_sync.clone());
    }

    config.save(config_path)?;

    println!();
    println!("+------------------------------------------------------------+");
    println!("|          PCOS NODE ENROLLMENT SUCCESSFUL!                  |");
    println!("+------------------------------------------------------------+");
    println!("  Device ID     : {}", dev_id);
    println!("  Control Server: {}", config.server_url);
    println!("  Storage Folder: {}", default_sync);
    println!("  Config Path   : {}", config_path);
    println!("+------------------------------------------------------------+");
    println!("To start syncing files: pcos-agent --daemon");
    println!();

    Ok(())
}
