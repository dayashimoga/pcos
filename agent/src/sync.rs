use crate::config::AgentConfig;
use crate::db::LocalDb;
use crate::delta;
use reqwest::multipart;
use std::path::Path;

/// Main sync loop — periodically uploads pending files to the server using content-defined chunking.
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
                    match upload_file(&client, config, path, hash, *size).await {
                        Ok(remote_id) => {
                            db.mark_synced(path, &remote_id).ok();
                            db.log_sync(path, "upload", "success", None).ok();
                            tracing::info!(path = %path, remote_id = %remote_id, "File synced successfully");
                        }
                        Err(e) => {
                            db.log_sync(path, "upload", "failed", Some(&e.to_string()))
                                .ok();
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

/// Upload a file to the server using content-defined chunking for large files.
async fn upload_file(
    client: &reqwest::Client,
    config: &AgentConfig,
    path: &str,
    expected_hash: &str,
    size: i64,
) -> anyhow::Result<String> {
    let file_path = Path::new(path);
    if !file_path.exists() {
        anyhow::bail!("Local file no longer exists: {}", path);
    }

    // Compute content-defined chunks
    let chunks = delta::compute_chunks(file_path)
        .await
        .map_err(|e| anyhow::anyhow!("Failed to compute chunks: {e}"))?;

    tracing::debug!(
        path = %path,
        size_bytes = size,
        chunk_count = chunks.len(),
        hash = %expected_hash,
        "Prepared content-defined chunks"
    );

    let filename = file_path
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    // Use chunked upload if file has multiple chunks and size > 1 MB
    if chunks.len() > 1 && size > 1024 * 1024 {
        use tokio::io::{AsyncReadExt, AsyncSeekExt};
        let upload_id = uuid::Uuid::new_v4();
        let mut file = tokio::fs::File::open(file_path).await?;

        for chunk in &chunks {
            file.seek(std::io::SeekFrom::Start(chunk.offset)).await?;
            let mut chunk_bytes = vec![0u8; chunk.length];
            file.read_exact(&mut chunk_bytes).await?;

            let part = multipart::Part::bytes(chunk_bytes)
                .file_name(format!("chunk_{:06}", chunk.index))
                .mime_str("application/octet-stream")?;

            let form = multipart::Form::new()
                .text("upload_id", upload_id.to_string())
                .text("chunk_index", chunk.index.to_string())
                .part("chunk", part);

            let resp = client
                .post(format!("{}/api/v1/files/upload/chunk", config.server_url))
                .bearer_auth(&config.auth_token)
                .multipart(form)
                .send()
                .await?;

            if !resp.status().is_success() {
                anyhow::bail!("Chunk {} upload failed: {}", chunk.index, resp.status());
            }
        }

        // Complete chunked upload
        let complete_resp = client
            .post(format!(
                "{}/api/v1/files/upload/complete",
                config.server_url
            ))
            .bearer_auth(&config.auth_token)
            .json(&serde_json::json!({
                "upload_id": upload_id.to_string(),
                "filename": filename,
                "total_chunks": chunks.len(),
            }))
            .send()
            .await?;

        if !complete_resp.status().is_success() {
            let status = complete_resp.status();
            let body = complete_resp.text().await.unwrap_or_default();
            anyhow::bail!("Complete upload failed: {} - {}", status, body);
        }

        let body: serde_json::Value = complete_resp.json().await?;
        let remote_id = body["file"]["id"].as_str().unwrap_or("unknown").to_string();

        return Ok(remote_id);
    }

    // Single upload for smaller files
    let data = tokio::fs::read(path).await?;
    let file_part = multipart::Part::bytes(data)
        .file_name(filename)
        .mime_str("application/octet-stream")?;

    let form = multipart::Form::new().part("file", file_part);

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
    let remote_id = body["file"]["id"].as_str().unwrap_or("unknown").to_string();

    Ok(remote_id)
}
