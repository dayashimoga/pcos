//! PCOS Agent Offline Transfer & Sync Queue
//!
//! Provides persistent disk-backed queuing for transfers and delta-sync operations
//! when disconnected from the control plane or when offline. Automatically flushes
//! and reconciles once connectivity is restored.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use tracing::warn;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct QueuedTransfer {
    pub id: String,
    pub local_path: String,
    pub relative_path: String,
    pub storage_node_id: Option<String>,
    pub op: String, // "upload", "sync", "delete", "replicate"
    pub size_bytes: u64,
    pub sha256: Option<String>,
    pub priority: u32, // Higher number = higher priority
    pub attempts: u32,
    pub created_at: String,
}

#[derive(Debug)]
pub struct OfflineQueue {
    queue_file: PathBuf,
}

impl OfflineQueue {
    pub fn new(queue_file: PathBuf) -> Self {
        Self { queue_file }
    }

    /// Read all queued transfers from disk
    pub fn list(&self) -> Vec<QueuedTransfer> {
        if !self.queue_file.exists() {
            return Vec::new();
        }

        match fs::read_to_string(&self.queue_file) {
            Ok(content) => serde_json::from_str(&content).unwrap_or_default(),
            Err(e) => {
                warn!(error = %e, "Failed to read offline queue file");
                Vec::new()
            }
        }
    }

    /// Save queued transfers to disk atomically
    fn save(&self, items: &[QueuedTransfer]) -> std::io::Result<()> {
        if let Some(parent) = self.queue_file.parent() {
            fs::create_dir_all(parent)?;
        }
        let json = serde_json::to_string_pretty(items)?;
        let tmp_file = self.queue_file.with_extension("tmp");
        fs::write(&tmp_file, json)?;
        fs::rename(tmp_file, &self.queue_file)?;
        Ok(())
    }

    /// Enqueue a transfer, ordered by priority (highest first)
    pub fn enqueue(&self, transfer: QueuedTransfer) -> std::io::Result<()> {
        let mut items = self.list();
        // Remove existing item with same ID if present
        items.retain(|i| i.id != transfer.id);
        items.push(transfer);
        // Sort descending by priority
        items.sort_by(|a, b| b.priority.cmp(&a.priority));
        self.save(&items)
    }

    /// Dequeue / remove an item by ID once completed
    pub fn dequeue(&self, id: &str) -> std::io::Result<Option<QueuedTransfer>> {
        let mut items = self.list();
        if let Some(pos) = items.iter().position(|i| i.id == id) {
            let removed = items.remove(pos);
            self.save(&items)?;
            Ok(Some(removed))
        } else {
            Ok(None)
        }
    }

    /// Drain all items from the queue
    pub fn drain(&self) -> std::io::Result<Vec<QueuedTransfer>> {
        let items = self.list();
        self.save(&[])?;
        Ok(items)
    }

    /// Get current queue length
    pub fn len(&self) -> usize {
        self.list().len()
    }

    /// Is queue empty
    pub fn is_empty(&self) -> bool {
        self.list().is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn get_test_queue_path(name: &str) -> PathBuf {
        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!("pcos_queue_test_{}_{}.json", name, ts));
        if path.exists() {
            let _ = fs::remove_file(&path);
        }
        path
    }

    #[test]
    fn test_offline_queue_enqueue_dequeue() {
        let q_file = get_test_queue_path("enqueue_dequeue");
        let q = OfflineQueue::new(q_file.clone());

        assert!(q.is_empty());

        let t1 = QueuedTransfer {
            id: "xfer_1".into(),
            local_path: "/data/photo1.jpg".into(),
            relative_path: "photos/photo1.jpg".into(),
            storage_node_id: Some("sn_ssd1".into()),
            op: "upload".into(),
            size_bytes: 4096,
            sha256: Some("hash1".into()),
            priority: 10,
            attempts: 0,
            created_at: "2026-10-13T00:00:00Z".into(),
        };

        q.enqueue(t1.clone()).unwrap();
        assert_eq!(q.len(), 1);

        let items = q.list();
        assert_eq!(items[0].id, "xfer_1");

        let dequeued = q.dequeue("xfer_1").unwrap();
        assert_eq!(dequeued.unwrap().id, "xfer_1");
        assert!(q.is_empty());
        let _ = fs::remove_file(&q_file);
    }

    #[test]
    fn test_offline_queue_priority_ordering() {
        let q_file = get_test_queue_path("priority");
        let q = OfflineQueue::new(q_file.clone());

        let low = QueuedTransfer {
            id: "low_pri".into(),
            local_path: "/data/archive.tar".into(),
            relative_path: "archive.tar".into(),
            storage_node_id: None,
            op: "upload".into(),
            size_bytes: 1000000,
            sha256: None,
            priority: 5,
            attempts: 0,
            created_at: "2026-10-13T00:00:00Z".into(),
        };

        let high = QueuedTransfer {
            id: "high_pri".into(),
            local_path: "/data/doc.pdf".into(),
            relative_path: "doc.pdf".into(),
            storage_node_id: None,
            op: "upload".into(),
            size_bytes: 50000,
            sha256: None,
            priority: 50,
            attempts: 0,
            created_at: "2026-10-13T00:00:00Z".into(),
        };

        q.enqueue(low).unwrap();
        q.enqueue(high).unwrap();

        let items = q.list();
        assert_eq!(items.len(), 2);
        assert_eq!(items[0].id, "high_pri"); // higher priority must be first
        assert_eq!(items[1].id, "low_pri");
        let _ = fs::remove_file(&q_file);
    }

    #[test]
    fn test_offline_queue_drain() {
        let q_file = get_test_queue_path("drain");
        let q = OfflineQueue::new(q_file.clone());

        let t1 = QueuedTransfer {
            id: "t1".into(),
            local_path: "/data/1".into(),
            relative_path: "1".into(),
            storage_node_id: None,
            op: "upload".into(),
            size_bytes: 10,
            sha256: None,
            priority: 1,
            attempts: 0,
            created_at: "2026-10-13T00:00:00Z".into(),
        };

        q.enqueue(t1).unwrap();
        assert_eq!(q.len(), 1);

        let drained = q.drain().unwrap();
        assert_eq!(drained.len(), 1);
        assert!(q.is_empty());
        let _ = fs::remove_file(&q_file);
    }
}
