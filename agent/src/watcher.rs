use crate::db::LocalDb;
use notify::{Config, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use sha2::{Digest, Sha256};
use std::path::Path;
use tokio::sync::mpsc;

/// Watch folders for filesystem changes and update the local DB.
pub async fn watch_folders(folders: &[String], db: &LocalDb) -> anyhow::Result<()> {
    let (tx, mut rx) = mpsc::channel(1000);

    let mut watcher = RecommendedWatcher::new(
        move |event: Result<notify::Event, notify::Error>| {
            if let Ok(evt) = event {
                let _ = tx.blocking_send(evt);
            }
        },
        Config::default(),
    )?;

    for folder in folders {
        let path = Path::new(folder);
        if path.exists() {
            watcher.watch(path, RecursiveMode::Recursive)?;
            tracing::info!(path = %folder, "Watching folder");

            // Initial scan
            scan_directory(path, db)?;
        } else {
            tracing::warn!(path = %folder, "Sync folder does not exist, skipping");
        }
    }

    // Process filesystem events
    while let Some(event) = rx.recv().await {
        match event.kind {
            EventKind::Create(_) | EventKind::Modify(_) => {
                for path in &event.paths {
                    if path.is_file() {
                        if let Err(e) = index_file(path, db) {
                            tracing::error!(path = %path.display(), error = %e, "Failed to index file");
                        }
                    }
                }
            }
            EventKind::Remove(_) => {
                for path in &event.paths {
                    let path_str = path.to_string_lossy().to_string();
                    db.remove_file(&path_str).ok();
                    db.log_sync(&path_str, "delete", "pending", None).ok();
                    tracing::debug!(path = %path_str, "File removed from cache");
                }
            }
            _ => {}
        }
    }

    Ok(())
}

/// Recursively scan a directory and index all files.
fn scan_directory(dir: &Path, db: &LocalDb) -> anyhow::Result<()> {
    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();

        if path.is_dir() {
            scan_directory(&path, db)?;
        } else if path.is_file() {
            index_file(&path, db)?;
        }
    }
    Ok(())
}

/// Compute SHA-256 hash and index a single file.
fn index_file(path: &Path, db: &LocalDb) -> anyhow::Result<()> {
    let metadata = std::fs::metadata(path)?;
    let size = metadata.len() as i64;
    let modified = metadata.modified()?.duration_since(std::time::UNIX_EPOCH)?.as_secs().to_string();

    // Compute SHA-256
    let data = std::fs::read(path)?;
    let mut hasher = Sha256::new();
    hasher.update(&data);
    let hash = hex::encode(hasher.finalize());

    let path_str = path.to_string_lossy().to_string();
    db.upsert_file(&path_str, &hash, size, &modified)?;

    tracing::debug!(path = %path_str, size = size, "File indexed");
    Ok(())
}
