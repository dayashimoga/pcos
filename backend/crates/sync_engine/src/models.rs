use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, sqlx::FromRow, Serialize)]
pub struct SyncState {
    pub id: Uuid,
    pub user_id: Uuid,
    pub device_id: Uuid,
    pub file_entry_id: Uuid,
    pub version: i64,
    pub status: String, // "synced", "pending", "conflict"
    pub last_synced_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize)]
pub struct SyncFolder {
    pub id: Uuid,
    pub user_id: Uuid,
    pub device_id: Uuid,
    pub local_path: String,
    pub remote_folder_id: Option<Uuid>,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
pub struct ChangeEvent {
    pub id: Uuid,
    pub file_entry_id: Uuid,
    pub change_type: String, // "created", "modified", "deleted", "moved"
    pub name: String,
    pub version: i64,
    pub timestamp: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct AddSyncFolderRequest {
    pub device_id: Uuid,
    pub local_path: String,
    pub remote_folder_id: Option<Uuid>,
}

#[derive(Debug, Deserialize)]
pub struct ResolveConflictRequest {
    pub file_entry_id: Uuid,
    pub resolution: String, // "keep_local", "keep_remote", "keep_both"
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncMessage {
    pub msg_type: String,
    pub payload: serde_json::Value,
}

#[derive(Debug, Serialize)]
pub struct SyncStatusResponse {
    pub device_id: Uuid,
    pub total_synced: i64,
    pub pending: i64,
    pub conflicts: i64,
    pub last_sync: Option<DateTime<Utc>>,
}
