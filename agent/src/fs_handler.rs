// PCOS Agent Physical Filesystem Handler
// Provides secure, path-confined filesystem operations (list, stat, read, write, delete)
// strictly jailed within declared physical storage roots.

use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Component, Path, PathBuf};
use std::time::SystemTime;

#[derive(Debug)]
pub enum FsError {
    PathTraversal(String),
    InvalidRoot(String),
    NotFound(String),
    PermissionDenied(String),
    Io(std::io::Error),
}

impl From<std::io::Error> for FsError {
    fn from(err: std::io::Error) -> Self {
        FsError::Io(err)
    }
}

impl std::fmt::Display for FsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FsError::PathTraversal(p) => write!(f, "Path traversal violation: '{}' escapes root", p),
            FsError::InvalidRoot(p) => write!(f, "Storage root inaccessible: '{}'", p),
            FsError::NotFound(p) => write!(f, "File/directory not found: '{}'", p),
            FsError::PermissionDenied(p) => write!(f, "Access denied: '{}'", p),
            FsError::Io(e) => write!(f, "I/O error: {}", e),
        }
    }
}

impl std::error::Error for FsError {}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FsEntry {
    pub name: String,
    pub relative_path: String,
    pub entry_type: String, // "file" or "folder"
    pub size_bytes: u64,
    pub modified_at: Option<String>,
    pub mime_type: Option<String>,
    pub is_readonly: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ListDirResult {
    pub relative_path: String,
    pub entries: Vec<FsEntry>,
    pub total_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatResult {
    pub exists: bool,
    pub entry: Option<FsEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReadChunkResult {
    pub relative_path: String,
    pub offset: u64,
    pub length: usize,
    pub total_size: u64,
    pub eof: bool,
    pub data_base64: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WriteChunkResult {
    pub relative_path: String,
    pub offset: u64,
    pub bytes_written: usize,
    pub total_size: u64,
}

pub struct FsHandler;

impl FsHandler {
    /// Strictly jail and resolve a relative path within a storage root.
    /// Rejects any path traversal attempts (`..`, absolute paths, symlink escapes).
    pub fn safe_resolve(root: &Path, rel_path: &str) -> Result<PathBuf, FsError> {
        // Ensure root exists
        let canonical_root = root
            .canonicalize()
            .map_err(|_| FsError::InvalidRoot(root.display().to_string()))?;

        // Sanitize rel_path: normalize separators and strip leading slashes
        let normalized = rel_path.replace('\\', "/");
        let cleaned = normalized
            .trim()
            .trim_start_matches('/');

        // Reject drive prefixes on any OS (e.g. C:, D:)
        if cleaned.len() >= 2 && cleaned.as_bytes()[1] == b':' && cleaned.as_bytes()[0].is_ascii_alphabetic() {
            return Err(FsError::PathTraversal(rel_path.to_string()));
        }

        // Check for suspicious components before path joining
        let path = Path::new(&cleaned);
        for component in path.components() {
            match component {
                Component::ParentDir => {
                    return Err(FsError::PathTraversal(rel_path.to_string()));
                }
                Component::RootDir | Component::Prefix(_) => {
                    return Err(FsError::PathTraversal(rel_path.to_string()));
                }
                Component::Normal(_) | Component::CurDir => {}
            }
        }

        let candidate = canonical_root.join(path);

        // If target exists, canonicalize to verify symlink does not escape root
        if candidate.exists() {
            let canonical_candidate = candidate
                .canonicalize()
                .map_err(|e| FsError::Io(e))?;

            if !canonical_candidate.starts_with(&canonical_root) {
                return Err(FsError::PathTraversal(rel_path.to_string()));
            }
            Ok(canonical_candidate)
        } else {
            // If candidate does not exist yet (e.g. for write/mkdir), ensure its parent is within root
            if let Some(parent) = candidate.parent() {
                if parent.exists() {
                    let canonical_parent = parent
                        .canonicalize()
                        .map_err(|e| FsError::Io(e))?;
                    if !canonical_parent.starts_with(&canonical_root) {
                        return Err(FsError::PathTraversal(rel_path.to_string()));
                    }
                }
            }
            Ok(candidate)
        }
    }

    /// List contents of a directory confined within root.
    pub fn list_dir(root: &Path, rel_path: &str) -> Result<ListDirResult, FsError> {
        let full_path = Self::safe_resolve(root, rel_path)?;

        if !full_path.exists() {
            return Err(FsError::NotFound(rel_path.to_string()));
        }

        if !full_path.is_dir() {
            return Err(FsError::InvalidRoot(format!("'{}' is not a directory", rel_path)));
        }

        let read_dir = fs::read_dir(&full_path).map_err(FsError::Io)?;
        let mut entries = Vec::new();

        let clean_rel = rel_path.replace('\\', "/").trim().trim_start_matches('/').to_string();

        for entry_res in read_dir {
            let entry = match entry_res {
                Ok(e) => e,
                Err(_) => continue, // Skip unreadable entries gracefully
            };

            let file_name = entry.file_name().to_string_lossy().to_string();

            // Skip hidden or system metadata files if needed, or include them
            let meta = match entry.metadata() {
                Ok(m) => m,
                Err(_) => continue,
            };

            let is_dir = meta.is_dir();
            let size = if is_dir { 0 } else { meta.len() };
            let modified = meta.modified().ok().and_then(format_system_time);

            let entry_rel = if clean_rel.is_empty() {
                file_name.clone()
            } else {
                format!("{}/{}", clean_rel.replace('\\', "/"), file_name)
            };

            let mime = if is_dir {
                None
            } else {
                Some(guess_mime_type(&file_name))
            };

            entries.push(FsEntry {
                name: file_name,
                relative_path: entry_rel,
                entry_type: if is_dir { "folder".into() } else { "file".into() },
                size_bytes: size,
                modified_at: modified,
                mime_type: mime,
                is_readonly: meta.permissions().readonly(),
            });
        }

        // Sort folders first, then files alphabetically
        entries.sort_by(|a, b| {
            match (a.entry_type == "folder", b.entry_type == "folder") {
                (true, false) => std::cmp::Ordering::Less,
                (false, true) => std::cmp::Ordering::Greater,
                _ => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
            }
        });

        let total = entries.len();
        Ok(ListDirResult {
            relative_path: clean_rel.to_string(),
            entries,
            total_count: total,
        })
    }

    /// Stat a specific file or folder.
    pub fn stat(root: &Path, rel_path: &str) -> Result<StatResult, FsError> {
        let full_path = match Self::safe_resolve(root, rel_path) {
            Ok(p) => p,
            Err(FsError::NotFound(_)) => return Ok(StatResult { exists: false, entry: None }),
            Err(e) => return Err(e),
        };

        if !full_path.exists() {
            return Ok(StatResult { exists: false, entry: None });
        }

        let meta = fs::metadata(&full_path).map_err(FsError::Io)?;
        let is_dir = meta.is_dir();
        let name = full_path
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| "root".into());

        let clean_rel = rel_path.replace('\\', "/").trim().trim_start_matches('/').to_string();

        let entry = FsEntry {
            name: name.clone(),
            relative_path: clean_rel.to_string(),
            entry_type: if is_dir { "folder".into() } else { "file".into() },
            size_bytes: if is_dir { 0 } else { meta.len() },
            modified_at: meta.modified().ok().and_then(format_system_time),
            mime_type: if is_dir { None } else { Some(guess_mime_type(&name)) },
            is_readonly: meta.permissions().readonly(),
        };

        Ok(StatResult {
            exists: true,
            entry: Some(entry),
        })
    }

    /// Read a chunk from a file within root, returning base64 encoded data.
    pub fn read_chunk(
        root: &Path,
        rel_path: &str,
        offset: u64,
        max_length: usize,
    ) -> Result<ReadChunkResult, FsError> {
        let full_path = Self::safe_resolve(root, rel_path)?;

        if !full_path.is_file() {
            return Err(FsError::NotFound(rel_path.to_string()));
        }

        let mut file = fs::File::open(&full_path).map_err(FsError::Io)?;
        let total_size = file.metadata().map_err(FsError::Io)?.len();

        if offset >= total_size {
            return Ok(ReadChunkResult {
                relative_path: rel_path.to_string(),
                offset,
                length: 0,
                total_size,
                eof: true,
                data_base64: String::new(),
            });
        }

        file.seek(SeekFrom::Start(offset)).map_err(FsError::Io)?;

        // Cap buffer to max 2MB per chunk for safety and memory stability
        let read_len = max_length.min(2 * 1024 * 1024).min((total_size - offset) as usize);
        let mut buffer = vec![0u8; read_len];
        let bytes_read = file.read(&mut buffer).map_err(FsError::Io)?;
        buffer.truncate(bytes_read);

        let is_eof = offset + (bytes_read as u64) >= total_size;

        // Base64 encode using simple custom encoder or hex
        let b64 = base64_encode(&buffer);

        Ok(ReadChunkResult {
            relative_path: rel_path.to_string(),
            offset,
            length: bytes_read,
            total_size,
            eof: is_eof,
            data_base64: b64,
        })
    }

    /// Write a chunk to a file within root.
    pub fn write_chunk(
        root: &Path,
        rel_path: &str,
        offset: u64,
        data: &[u8],
    ) -> Result<WriteChunkResult, FsError> {
        let full_path = Self::safe_resolve(root, rel_path)?;

        // Ensure parent directory exists
        if let Some(parent) = full_path.parent() {
            fs::create_dir_all(parent).map_err(FsError::Io)?;
        }

        let mut file = fs::OpenOptions::new()
            .write(true)
            .create(true)
            .open(&full_path)
            .map_err(FsError::Io)?;

        file.seek(SeekFrom::Start(offset)).map_err(FsError::Io)?;
        file.write_all(data).map_err(FsError::Io)?;
        file.flush().map_err(FsError::Io)?;

        let total_size = file.metadata().map_err(FsError::Io)?.len();

        Ok(WriteChunkResult {
            relative_path: rel_path.to_string(),
            offset,
            bytes_written: data.len(),
            total_size,
        })
    }

    /// Delete a file or directory within root.
    pub fn delete(root: &Path, rel_path: &str, recursive: bool) -> Result<bool, FsError> {
        let full_path = Self::safe_resolve(root, rel_path)?;

        // Never allow deleting the root directory itself
        let canonical_root = root.canonicalize().map_err(|e| FsError::Io(e))?;
        if full_path == canonical_root {
            return Err(FsError::PermissionDenied("Cannot delete storage root directory".into()));
        }

        if !full_path.exists() {
            return Ok(false);
        }

        if full_path.is_dir() {
            if recursive {
                fs::remove_dir_all(&full_path).map_err(FsError::Io)?;
            } else {
                fs::remove_dir(&full_path).map_err(FsError::Io)?;
            }
        } else {
            fs::remove_file(&full_path).map_err(FsError::Io)?;
        }

        Ok(true)
    }

    /// Create a directory within root.
    pub fn mkdir(root: &Path, rel_path: &str) -> Result<bool, FsError> {
        let full_path = Self::safe_resolve(root, rel_path)?;
        if full_path.exists() {
            return Ok(false);
        }
        fs::create_dir_all(&full_path).map_err(FsError::Io)?;
        Ok(true)
    }
}

/// Simple RFC 4648 Base64 Encoder without extra crate dependencies
pub fn base64_encode(data: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity((data.len() + 2) / 3 * 4);

    for chunk in data.chunks(3) {
        let b0 = chunk[0];
        let b1 = if chunk.len() > 1 { chunk[1] } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] } else { 0 };

        let n = ((b0 as u32) << 16) | ((b1 as u32) << 8) | (b2 as u32);

        out.push(TABLE[((n >> 18) & 63) as usize] as char);
        out.push(TABLE[((n >> 12) & 63) as usize] as char);

        if chunk.len() > 1 {
            out.push(TABLE[((n >> 6) & 63) as usize] as char);
        } else {
            out.push('=');
        }

        if chunk.len() > 2 {
            out.push(TABLE[(n & 63) as usize] as char);
        } else {
            out.push('=');
        }
    }

    out
}

/// Simple RFC 4648 Base64 Decoder
pub fn base64_decode(encoded: &str) -> Result<Vec<u8>, String> {
    let clean = encoded.trim();
    if clean.is_empty() {
        return Ok(Vec::new());
    }

    let mut out = Vec::with_capacity(clean.len() * 3 / 4);
    let mut buffer: u32 = 0;
    let mut bits = 0;

    for ch in clean.chars() {
        if ch == '=' {
            break;
        }
        let val = match ch {
            'A'..='Z' => (ch as u32) - ('A' as u32),
            'a'..='z' => (ch as u32) - ('a' as u32) + 26,
            '0'..='9' => (ch as u32) - ('0' as u32) + 52,
            '+' => 62,
            '/' => 63,
            c if c.is_whitespace() => continue,
            _ => return Err(format!("Invalid base64 character: {}", ch)),
        };

        buffer = (buffer << 6) | val;
        bits += 6;

        if bits >= 8 {
            bits -= 8;
            out.push(((buffer >> bits) & 0xFF) as u8);
        }
    }

    Ok(out)
}

fn format_system_time(time: SystemTime) -> Option<String> {
    let duration = time.duration_since(SystemTime::UNIX_EPOCH).ok()?;
    let secs = duration.as_secs();
    Some(chrono::DateTime::from_timestamp(secs as i64, 0)?
        .to_rfc3339())
}

fn guess_mime_type(filename: &str) -> String {
    let lower = filename.to_lowercase();
    let ext = lower.split('.').last().unwrap_or("");

    match ext {
        // Video
        "mp4" | "m4v" => "video/mp4",
        "mkv" => "video/x-matroska",
        "webm" => "video/webm",
        "mov" => "video/quicktime",
        "avi" => "video/x-msvideo",

        // Audio
        "mp3" => "audio/mpeg",
        "flac" => "audio/flac",
        "wav" => "audio/wav",
        "m4a" => "audio/mp4",
        "ogg" => "audio/ogg",

        // Images
        "jpg" | "jpeg" => "image/jpeg",
        "png" => "image/png",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "svg" => "image/svg+xml",

        // Documents
        "pdf" => "application/pdf",
        "json" => "application/json",
        "txt" | "md" | "rs" | "ts" | "dart" | "toml" | "yaml" | "yml" => "text/plain",
        "html" | "htm" => "text/html",
        "zip" => "application/zip",
        "tar" => "application/x-tar",
        "gz" => "application/gzip",

        _ => "application/octet-stream",
    }
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn test_base64_roundtrip() {
        let original = b"Hello PCOS personal cloud OS! 1234567890 \x00\xFF";
        let encoded = base64_encode(original);
        let decoded = base64_decode(&encoded).expect("Decode should succeed");
        assert_eq!(decoded, original);
    }

    #[test]
    fn test_path_traversal_rejection() {
        let temp_dir = std::env::temp_dir().join("pcos_test_jail");
        let _ = fs::create_dir_all(&temp_dir);

        // Attempts to escape using ..
        assert!(FsHandler::safe_resolve(&temp_dir, "../foo").is_err());
        assert!(FsHandler::safe_resolve(&temp_dir, "subdir/../../outside").is_err());
        assert!(FsHandler::safe_resolve(&temp_dir, "..\\..\\windows").is_err());

        // Valid relative paths must succeed
        let valid = FsHandler::safe_resolve(&temp_dir, "my_file.txt");
        assert!(valid.is_ok());

        let _ = fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn test_fs_read_write_delete_lifecycle() {
        let temp_dir = std::env::temp_dir().join("pcos_test_crud");
        let _ = fs::create_dir_all(&temp_dir);

        let test_content = b"Personal Cloud OS Real Physical Storage!";
        let rel_path = "nested/test_doc.txt";

        // Write chunk
        let write_res = FsHandler::write_chunk(&temp_dir, rel_path, 0, test_content).unwrap();
        assert_eq!(write_res.bytes_written, test_content.len());

        // Stat
        let stat_res = FsHandler::stat(&temp_dir, rel_path).unwrap();
        assert!(stat_res.exists);
        assert_eq!(stat_res.entry.unwrap().size_bytes, test_content.len() as u64);

        // List dir
        let list_res = FsHandler::list_dir(&temp_dir, "nested").unwrap();
        assert_eq!(list_res.total_count, 1);
        assert_eq!(list_res.entries[0].name, "test_doc.txt");

        // Read chunk
        let read_res = FsHandler::read_chunk(&temp_dir, rel_path, 0, 1024).unwrap();
        assert_eq!(read_res.length, test_content.len());
        assert!(read_res.eof);
        let decoded = base64_decode(&read_res.data_base64).unwrap();
        assert_eq!(decoded, test_content);

        // Delete
        let del_res = FsHandler::delete(&temp_dir, rel_path, false).unwrap();
        assert!(del_res);
        assert!(!FsHandler::stat(&temp_dir, rel_path).unwrap().exists);

        let _ = fs::remove_dir_all(&temp_dir);
    }
}
