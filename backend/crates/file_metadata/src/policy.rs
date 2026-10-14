//! PCOS Unified Storage Policy Engine & Placement Evaluator
//!
//! Automatically classifies files by MIME type, extension, capacity, and durability goals
//! to route photos to fast SSD pools, videos to high-capacity HDDs, documents to SSD/NAS,
//! and critical backups to independent redundant replicas.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum StorageCategory {
    Photos,
    Videos,
    Audio,
    Documents,
    Backups,
    Important,
    Custom(String),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum StorageType {
    Ssd,
    Hdd,
    Usb,
    Nas,
    Any,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlacementEvaluation {
    pub category: StorageCategory,
    pub target_storage_type: StorageType,
    pub replica_count: u32,
    pub availability_tier: String,
    pub rule_name: String,
}

pub fn evaluate_placement(file_name: &str, mime_type: Option<&str>) -> PlacementEvaluation {
    let lower_name = file_name.to_lowercase();
    let lower_mime = mime_type.unwrap_or("").to_lowercase();

    if lower_mime.starts_with("image/")
        || lower_name.ends_with(".jpg")
        || lower_name.ends_with(".jpeg")
        || lower_name.ends_with(".png")
        || lower_name.ends_with(".webp")
        || lower_name.ends_with(".heic")
        || lower_name.ends_with(".raw")
    {
        PlacementEvaluation {
            category: StorageCategory::Photos,
            target_storage_type: StorageType::Ssd,
            replica_count: 1,
            availability_tier: "local_only".to_string(),
            rule_name: "Default Photos -> High-Speed SSD Pool Policy".to_string(),
        }
    } else if lower_mime.starts_with("video/")
        || lower_name.ends_with(".mp4")
        || lower_name.ends_with(".mkv")
        || lower_name.ends_with(".mov")
        || lower_name.ends_with(".avi")
        || lower_name.ends_with(".webm")
    {
        PlacementEvaluation {
            category: StorageCategory::Videos,
            target_storage_type: StorageType::Hdd,
            replica_count: 1,
            availability_tier: "local_only".to_string(),
            rule_name: "Default Videos -> Massive Capacity HDD Pool Policy".to_string(),
        }
    } else if lower_mime.starts_with("audio/")
        || lower_name.ends_with(".mp3")
        || lower_name.ends_with(".flac")
        || lower_name.ends_with(".wav")
        || lower_name.ends_with(".ogg")
        || lower_name.ends_with(".m4a")
    {
        PlacementEvaluation {
            category: StorageCategory::Audio,
            target_storage_type: StorageType::Any,
            replica_count: 1,
            availability_tier: "local_only".to_string(),
            rule_name: "Default Audio -> Music Library Policy".to_string(),
        }
    } else if lower_name.ends_with(".tar")
        || lower_name.ends_with(".zip")
        || lower_name.ends_with(".bak")
        || lower_name.ends_with(".dump")
        || lower_name.ends_with(".gz")
    {
        PlacementEvaluation {
            category: StorageCategory::Backups,
            target_storage_type: StorageType::Usb,
            replica_count: 2,
            availability_tier: "always_available".to_string(),
            rule_name: "Default System Backups & Archives Policy".to_string(),
        }
    } else {
        PlacementEvaluation {
            category: StorageCategory::Documents,
            target_storage_type: StorageType::Ssd,
            replica_count: 1,
            availability_tier: "any_device".to_string(),
            rule_name: "Default Documents -> Fast SSD / NAS Policy".to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_evaluate_photos_routes_to_ssd() {
        let eval = evaluate_placement("family_vacation.jpg", Some("image/jpeg"));
        assert_eq!(eval.category, StorageCategory::Photos);
        assert_eq!(eval.target_storage_type, StorageType::Ssd);
        assert_eq!(eval.replica_count, 1);
    }

    #[test]
    fn test_evaluate_videos_routes_to_hdd() {
        let eval = evaluate_placement("drone_4k_sample.mp4", Some("video/mp4"));
        assert_eq!(eval.category, StorageCategory::Videos);
        assert_eq!(eval.target_storage_type, StorageType::Hdd);
        assert_eq!(eval.replica_count, 1);
    }

    #[test]
    fn test_evaluate_backups_requires_two_replicas() {
        let eval = evaluate_placement("system_backup_2026.bak", None);
        assert_eq!(eval.category, StorageCategory::Backups);
        assert_eq!(eval.target_storage_type, StorageType::Usb);
        assert_eq!(eval.replica_count, 2);
    }

    #[test]
    fn test_evaluate_documents_routes_to_ssd() {
        let eval = evaluate_placement("financial_report.pdf", Some("application/pdf"));
        assert_eq!(eval.category, StorageCategory::Documents);
        assert_eq!(eval.target_storage_type, StorageType::Ssd);
    }
}
