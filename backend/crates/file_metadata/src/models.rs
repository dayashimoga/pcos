use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

/// Database model for files and folders.
#[derive(Debug, Clone, sqlx::FromRow, Serialize)]
pub struct FileEntry {
    pub id: Uuid,
    pub user_id: Uuid,
    pub parent_id: Option<Uuid>,
    pub name: String,
    pub entry_type: String, // "file" or "folder"
    pub mime_type: Option<String>,
    pub size_bytes: i64,
    pub sha256_hash: Option<String>,
    pub storage_path: Option<String>,
    pub is_trashed: bool,
    pub trashed_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Request to create a folder.
#[derive(Debug, Deserialize, Validate)]
pub struct CreateFolderRequest {
    #[validate(length(
        min = 1,
        max = 255,
        message = "Folder name is required (max 255 chars)"
    ))]
    pub name: String,
    pub parent_id: Option<Uuid>,
}

/// Request to rename a file or folder.
#[derive(Debug, Deserialize, Validate)]
pub struct RenameRequest {
    #[validate(length(min = 1, max = 255, message = "Name is required"))]
    pub name: String,
}

/// Request to move a file or folder.
#[derive(Debug, Deserialize)]
pub struct MoveRequest {
    pub target_folder_id: Option<Uuid>, // None = root
}

/// Response for file/folder listing.
#[derive(Debug, Serialize)]
pub struct FileListResponse {
    pub entries: Vec<FileEntryResponse>,
    pub total: i64,
    pub path: Vec<BreadcrumbItem>,
}

#[derive(Debug, Serialize)]
pub struct BreadcrumbItem {
    pub id: Option<Uuid>,
    pub name: String,
}

/// Response DTO for a file entry.
#[derive(Debug, Serialize, Clone)]
pub struct FileEntryResponse {
    pub id: Uuid,
    pub parent_id: Option<Uuid>,
    pub name: String,
    pub entry_type: String,
    pub mime_type: Option<String>,
    pub size_bytes: i64,
    pub sha256_hash: Option<String>,
    pub is_trashed: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl From<FileEntry> for FileEntryResponse {
    fn from(f: FileEntry) -> Self {
        Self {
            id: f.id,
            parent_id: f.parent_id,
            name: f.name,
            entry_type: f.entry_type,
            mime_type: f.mime_type,
            size_bytes: f.size_bytes,
            sha256_hash: f.sha256_hash,
            is_trashed: f.is_trashed,
            created_at: f.created_at,
            updated_at: f.updated_at,
        }
    }
}

/// Response for storage statistics.
#[derive(Debug, Serialize)]
pub struct StorageStatsResponse {
    pub total_files: i64,
    pub total_folders: i64,
    pub total_size_bytes: i64,
    pub trashed_items: i64,
}

/// Chunked upload initiation / completion request.
#[derive(Debug, Deserialize)]
pub struct ChunkedUploadRequest {
    pub upload_id: Uuid,
    pub filename: String,
    pub parent_id: Option<Uuid>,
    pub total_size: i64,
    pub total_chunks: i32,
}

#[derive(Debug, Serialize)]
pub struct UploadResponse {
    pub file: FileEntryResponse,
}

#[derive(Debug, Serialize)]
pub struct ChunkUploadResponse {
    pub upload_id: Uuid,
    pub chunk_index: i32,
    pub received: bool,
}
