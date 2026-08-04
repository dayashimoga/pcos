//! Delta sync module — only upload changed bytes using content-defined chunking.
//!
//! Uses a rolling hash (Rabin-like) to split files into variable-size chunks.
//! On re-upload, only new/modified chunks are sent to the server.

use sha2::{Sha256, Digest};
use std::path::Path;

/// Minimum chunk size: 64 KB
const MIN_CHUNK: usize = 64 * 1024;
/// Average target chunk size: 256 KB
const AVG_CHUNK: usize = 256 * 1024;
/// Maximum chunk size: 1 MB
const MAX_CHUNK: usize = 1024 * 1024;
/// Rolling hash mask for average chunk boundary detection
const MASK: u32 = (AVG_CHUNK as u32) - 1; // Works when AVG_CHUNK is power of 2

/// A content-defined chunk with its hash and byte range.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ChunkInfo {
    pub index: usize,
    pub offset: u64,
    pub length: usize,
    pub hash: String,
}

/// Split file into content-defined chunks using rolling hash.
pub async fn compute_chunks(path: &Path) -> Result<Vec<ChunkInfo>, Box<dyn std::error::Error + Send + Sync>> {
    let data = tokio::fs::read(path).await?;
    Ok(split_into_chunks(&data))
}

/// Split byte slice into content-defined chunks.
fn split_into_chunks(data: &[u8]) -> Vec<ChunkInfo> {
    let mut chunks = Vec::new();
    let mut offset = 0usize;
    let mut chunk_start = 0usize;
    let mut rolling_hash: u32 = 0;
    let mut index = 0usize;

    while offset < data.len() {
        // Update rolling hash (simple Buzhash-style)
        rolling_hash = rolling_hash.wrapping_mul(31).wrapping_add(data[offset] as u32);
        let chunk_len = offset - chunk_start;

        // Check for chunk boundary
        let is_boundary = (chunk_len >= MIN_CHUNK && (rolling_hash & MASK) == 0)
            || chunk_len >= MAX_CHUNK;

        if is_boundary || offset == data.len() - 1 {
            let end = if is_boundary { offset } else { offset + 1 };
            let chunk_data = &data[chunk_start..end];

            // SHA-256 hash of chunk content
            let mut hasher = Sha256::new();
            hasher.update(chunk_data);
            let hash = format!("{:x}", hasher.finalize());

            chunks.push(ChunkInfo {
                index,
                offset: chunk_start as u64,
                length: chunk_data.len(),
                hash,
            });

            index += 1;
            chunk_start = end;
            rolling_hash = 0;
        }

        offset += 1;
    }

    chunks
}

/// Compare local chunks against server-known chunks.
/// Returns indices of chunks that need to be uploaded.
pub fn diff_chunks(local: &[ChunkInfo], server: &[ChunkInfo]) -> Vec<usize> {
    let server_hashes: std::collections::HashSet<&str> = server.iter()
        .map(|c| c.hash.as_str())
        .collect();

    local.iter()
        .filter(|c| !server_hashes.contains(c.hash.as_str()))
        .map(|c| c.index)
        .collect()
}

/// Compute file-level hash for quick change detection.
pub async fn file_hash(path: &Path) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let data = tokio::fs::read(path).await?;
    let mut hasher = Sha256::new();
    hasher.update(&data);
    Ok(format!("{:x}", hasher.finalize()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_split_deterministic() {
        let data = vec![0u8; AVG_CHUNK * 3];
        let chunks1 = split_into_chunks(&data);
        let chunks2 = split_into_chunks(&data);
        assert_eq!(chunks1.len(), chunks2.len());
        for (a, b) in chunks1.iter().zip(chunks2.iter()) {
            assert_eq!(a.hash, b.hash);
            assert_eq!(a.offset, b.offset);
            assert_eq!(a.length, b.length);
        }
    }

    #[test]
    fn test_diff_detects_changes() {
        let data1 = vec![1u8; AVG_CHUNK * 2];
        let data2 = vec![2u8; AVG_CHUNK * 2];
        let chunks1 = split_into_chunks(&data1);
        let chunks2 = split_into_chunks(&data2);
        let diff = diff_chunks(&chunks2, &chunks1);
        assert!(!diff.is_empty(), "Should detect changed chunks");
    }

    #[test]
    fn test_diff_no_changes() {
        let data = vec![42u8; AVG_CHUNK * 2];
        let chunks = split_into_chunks(&data);
        let diff = diff_chunks(&chunks, &chunks);
        assert!(diff.is_empty(), "Same data should produce no diff");
    }
}
