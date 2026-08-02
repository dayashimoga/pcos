use crate::config::AgentConfig;
use crate::db::LocalDb;
use reqwest::multipart;

/// Main sync loop — periodically uploads pending files to the server.
pub async fn sync_loop(config: &AgentConfig, db: &LocalDb) {
    let client = reqwest::Client::new();
    let interval = std::time::Duration::from_secs(config.sync_interval_secs);

    loop {
        match db.get_pending() {
            Ok(pending) => {
                if !pending.is_empty() {
                    tracing::info!(count = pending.len(), "Syncing pending files");
                }

                for (path, hash, size) in &pending {
                    match upload_file(&client, config, path, hash).await {
                        Ok(remote_id) => {
                            db.mark_synced(path, &remote_id).ok();
                            db.log_sync(path, "upload", "success", None).ok();
                            tracing::info!(path = %path, remote_id = %remote_id, "File synced");
                        }
                        Err(e) => {
                            db.log_sync(path, "upload", "failed", Some(&e.to_string())).ok();
                            tracing::error!(path = %path, error = %e, "Sync failed");
                        }
                    }
                }
            }
            Err(e) => {
                tracing::error!(error = %e, "Failed to get pending files");
            }
        }

        tokio::time::sleep(interval).await;
    }
}

/// Upload a single file to the server.
async fn upload_file(
    client: &reqwest::Client,
    config: &AgentConfig,
    path: &str,
    hash: &str,
) -> anyhow::Result<String> {
    let data = tokio::fs::read(path).await?;
    let filename = std::path::Path::new(path)
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    let file_part = multipart::Part::bytes(data)
        .file_name(filename.clone())
        .mime_str("application/octet-stream")?;

    let form = multipart::Form::new()
        .part("file", file_part);

    let resp = client
        .post(format!("{}/api/v1/files/upload", config.server_url))
        .bearer_auth(&config.auth_token)
        .multipart(form)
        .send()
        .await?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        anyhow::bail!("Upload failed: {} - {}", status, body);
    }

    let body: serde_json::Value = resp.json().await?;
    let remote_id = body["file"]["id"]
        .as_str()
        .unwrap_or("unknown")
        .to_string();

    Ok(remote_id)
}
