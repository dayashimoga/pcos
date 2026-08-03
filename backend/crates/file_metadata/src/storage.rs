use pcos_common::config::StorageConfig;
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};
use tokio::fs;
use tokio::io::AsyncWriteExt;
use uuid::Uuid;

/// Filesystem-based storage engine.
/// Files are stored under `<base_path>/<user_id>/<first 2 chars of file_id>/<file_id>`.
#[derive(Debug, Clone)]
pub struct StorageEngine {
    base_path: PathBuf,
}

impl StorageEngine {
    pub fn new(config: &StorageConfig) -> Self {
        Self {
            base_path: PathBuf::from(&config.base_path),
        }
    }

    /// Compute the storage path for a file.
    fn file_path(&self, user_id: Uuid, file_id: Uuid) -> PathBuf {
        let id_str = file_id.to_string();
        let prefix = &id_str[..2];
        self.base_path
            .join(user_id.to_string())
            .join(prefix)
            .join(&id_str)
    }

    /// Path for chunked upload temp directory.
    fn chunk_dir(&self, user_id: Uuid, upload_id: Uuid) -> PathBuf {
        self.base_path
            .join(user_id.to_string())
            .join("_chunks")
            .join(upload_id.to_string())
    }

    /// Store file data and return the storage path and SHA-256 hash.
    pub async fn store_file(
        &self,
        user_id: Uuid,
        file_id: Uuid,
        data: &[u8],
    ) -> Result<(String, String), std::io::Error> {
        let path = self.file_path(user_id, file_id);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).await?;
        }

        // Compute hash while writing
        let mut hasher = Sha256::new();
        hasher.update(data);
        let hash = hex::encode(hasher.finalize());

        fs::write(&path, data).await?;

        let relative_path = path
            .strip_prefix(&self.base_path)
            .unwrap_or(&path)
            .to_string_lossy()
            .to_string();

        tracing::info!(file_id = %file_id, size = data.len(), hash = %hash, "File stored");

        Ok((relative_path, hash))
    }

    /// Store a single chunk of a chunked upload.
    pub async fn store_chunk(
        &self,
        user_id: Uuid,
        upload_id: Uuid,
        chunk_index: i32,
        data: &[u8],
    ) -> Result<(), std::io::Error> {
        let dir = self.chunk_dir(user_id, upload_id);
        fs::create_dir_all(&dir).await?;

        let chunk_path = dir.join(format!("chunk_{:06}", chunk_index));
        fs::write(&chunk_path, data).await?;

        tracing::debug!(upload_id = %upload_id, chunk = chunk_index, size = data.len(), "Chunk stored");

        Ok(())
    }

    /// Assemble all chunks into a final file, returning storage path and hash.
    pub async fn assemble_chunks(
        &self,
        user_id: Uuid,
        upload_id: Uuid,
        file_id: Uuid,
        total_chunks: i32,
    ) -> Result<(String, String, i64), std::io::Error> {
        let chunk_dir = self.chunk_dir(user_id, upload_id);
        let file_path = self.file_path(user_id, file_id);

        if let Some(parent) = file_path.parent() {
            fs::create_dir_all(parent).await?;
        }

        let mut file = fs::File::create(&file_path).await?;
        let mut hasher = Sha256::new();
        let mut total_size: i64 = 0;

        for i in 0..total_chunks {
            let chunk_path = chunk_dir.join(format!("chunk_{:06}", i));
            let data = fs::read(&chunk_path).await?;
            hasher.update(&data);
            total_size += data.len() as i64;
            file.write_all(&data).await?;
        }

        file.flush().await?;
        drop(file);

        // Clean up chunks
        fs::remove_dir_all(&chunk_dir).await.ok();

        let hash = hex::encode(hasher.finalize());
        let relative_path = file_path
            .strip_prefix(&self.base_path)
            .unwrap_or(&file_path)
            .to_string_lossy()
            .to_string();

        tracing::info!(file_id = %file_id, size = total_size, hash = %hash, "Chunked upload assembled");

        Ok((relative_path, hash, total_size))
    }

    /// Read file data from storage.
    pub async fn read_file(&self, storage_path: &str) -> Result<Vec<u8>, std::io::Error> {
        let full_path = self.base_path.join(storage_path);
        fs::read(&full_path).await
    }

    /// Get the absolute filesystem path for a stored file (for streaming).
    pub fn absolute_path(&self, storage_path: &str) -> PathBuf {
        self.base_path.join(storage_path)
    }

    /// Delete a file from storage.
    pub async fn delete_file(&self, storage_path: &str) -> Result<(), std::io::Error> {
        let full_path = self.base_path.join(storage_path);
        if full_path.exists() {
            fs::remove_file(&full_path).await?;
            tracing::info!(path = %storage_path, "File deleted from storage");
        }
        Ok(())
    }

    /// Get total disk usage for a user.
    pub async fn user_disk_usage(&self, user_id: Uuid) -> Result<u64, std::io::Error> {
        let user_dir = self.base_path.join(user_id.to_string());
        if !user_dir.exists() {
            return Ok(0);
        }
        dir_size(&user_dir).await
    }
}

/// Recursively calculate directory size.
async fn dir_size(path: &Path) -> Result<u64, std::io::Error> {
    let mut total = 0u64;
    let mut entries = fs::read_dir(path).await?;

    while let Some(entry) = entries.next_entry().await? {
        let metadata = entry.metadata().await?;
        if metadata.is_dir() {
            total += Box::pin(dir_size(&entry.path())).await?;
        } else {
            total += metadata.len();
        }
    }

    Ok(total)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn test_engine() -> (StorageEngine, TempDir) {
        let tmp = TempDir::new().unwrap();
        let engine = StorageEngine::new(&pcos_common::config::StorageConfig {
            base_path: tmp.path().to_string_lossy().to_string(),
            max_upload_size_mb: 100,
        });
        (engine, tmp)
    }

    #[tokio::test]
    async fn test_store_and_read_file() {
        let (engine, _tmp) = test_engine();
        let user_id = Uuid::new_v4();
        let file_id = Uuid::new_v4();
        let data = b"Hello, PCOS!";

        let (path, hash) = engine.store_file(user_id, file_id, data).await.unwrap();
        assert!(!path.is_empty());
        assert!(!hash.is_empty());

        let read_data = engine.read_file(&path).await.unwrap();
        assert_eq!(read_data, data);
    }

    #[tokio::test]
    async fn test_chunked_upload() {
        let (engine, _tmp) = test_engine();
        let user_id = Uuid::new_v4();
        let upload_id = Uuid::new_v4();
        let file_id = Uuid::new_v4();

        engine
            .store_chunk(user_id, upload_id, 0, b"chunk0")
            .await
            .unwrap();
        engine
            .store_chunk(user_id, upload_id, 1, b"chunk1")
            .await
            .unwrap();

        let (path, hash, size) = engine
            .assemble_chunks(user_id, upload_id, file_id, 2)
            .await
            .unwrap();
        assert_eq!(size, 12);

        let data = engine.read_file(&path).await.unwrap();
        assert_eq!(data, b"chunk0chunk1");
    }

    #[tokio::test]
    async fn test_delete_file() {
        let (engine, _tmp) = test_engine();
        let user_id = Uuid::new_v4();
        let file_id = Uuid::new_v4();

        let (path, _) = engine
            .store_file(user_id, file_id, b"delete me")
            .await
            .unwrap();
        engine.delete_file(&path).await.unwrap();

        assert!(engine.read_file(&path).await.is_err());
    }
}
