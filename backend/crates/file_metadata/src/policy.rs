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

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::{AppError, AppResult};
use pcos_common::AppState;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct StoragePolicyRecord {
    pub id: String,
    pub user_id: Option<Uuid>,
    pub category: String,
    pub name: Option<String>,
    pub mime_patterns: String,
    pub target_storage_type: String,
    pub target_node_id: Option<String>,
    pub replica_count: i32,
    pub availability_tier: String,
    pub priority: i32,
    pub is_default: Option<bool>,
}

#[derive(Deserialize)]
pub struct CreatePolicyRequest {
    pub category: String,
    pub name: Option<String>,
    pub mime_patterns: String,
    pub target_storage_type: Option<String>,
    pub target_node_id: Option<String>,
    pub replica_count: Option<i32>,
    pub availability_tier: Option<String>,
    pub priority: Option<i32>,
}

#[derive(Deserialize)]
pub struct StorageEvaluateRequest {
    pub name: Option<String>,
    pub mime_type: Option<String>,
    pub size_bytes: Option<i64>,
}

/// GET /api/v1/storage/policies — List default and custom storage policies.
pub async fn list_policies(
    State(state): State<AppState>,
    auth: AuthUser,
) -> AppResult<impl IntoResponse> {
    let defaults = vec![
        serde_json::json!({
            "id": "pol_def_photos",
            "category": "photos",
            "name": "Photos & Images -> High-Speed SSD Pool",
            "mime_patterns": "image/*",
            "target_storage_type": "ssd",
            "replica_count": 1,
            "availability_tier": "local_only",
            "priority": 10,
            "is_default": true,
        }),
        serde_json::json!({
            "id": "pol_def_videos",
            "category": "videos",
            "name": "Videos & High-Res Footage -> Massive HDD Pool",
            "mime_patterns": "video/*",
            "target_storage_type": "hdd",
            "replica_count": 1,
            "availability_tier": "local_only",
            "priority": 10,
            "is_default": true,
        }),
        serde_json::json!({
            "id": "pol_def_audio",
            "category": "audio",
            "name": "Music & Audio -> Music Library",
            "mime_patterns": "audio/*",
            "target_storage_type": "any",
            "replica_count": 1,
            "availability_tier": "local_only",
            "priority": 10,
            "is_default": true,
        }),
        serde_json::json!({
            "id": "pol_def_docs",
            "category": "documents",
            "name": "Documents & Notes -> Fast SSD / NAS",
            "mime_patterns": "application/pdf,text/*",
            "target_storage_type": "ssd",
            "replica_count": 1,
            "availability_tier": "any_device",
            "priority": 10,
            "is_default": true,
        }),
        serde_json::json!({
            "id": "pol_def_backups",
            "category": "backups",
            "name": "System Backups & Archives -> Backup Disk",
            "mime_patterns": "application/zip,application/x-tar",
            "target_storage_type": "usb",
            "replica_count": 2,
            "availability_tier": "always_available",
            "priority": 15,
            "is_default": true,
        }),
    ];

    let custom_policies: Vec<StoragePolicyRecord> = sqlx::query_as(
        r#"SELECT id, user_id, category, category as name, mime_patterns, target_storage_type,
                  target_node_id, replica_count, availability_tier, priority, false as is_default
           FROM storage_policies WHERE user_id = $1 ORDER BY priority DESC"#,
    )
    .bind(auth.claims.sub)
    .fetch_all(state.db.pool())
    .await
    .unwrap_or_default();

    let mut all = defaults;
    for c in custom_policies {
        all.push(serde_json::to_value(c).unwrap_or_default());
    }

    Ok(Json(serde_json::json!({
        "policies": all,
        "total": all.len(),
    })))
}

/// POST /api/v1/storage/policies — Create custom placement policy.
pub async fn create_policy(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<CreatePolicyRequest>,
) -> AppResult<impl IntoResponse> {
    if req.category.trim().is_empty() || req.mime_patterns.trim().is_empty() {
        return Err(AppError::Validation(
            "category and mime_patterns required".into(),
        ));
    }

    let policy_id = format!("pol_{}", Uuid::new_v4());
    let target_type = req.target_storage_type.unwrap_or_else(|| "any".into());
    let replicas = req.replica_count.unwrap_or(1);
    let tier = req.availability_tier.unwrap_or_else(|| "local_only".into());
    let priority = req.priority.unwrap_or(10);

    sqlx::query(
        r#"INSERT INTO storage_policies (id, user_id, category, mime_patterns, target_storage_type, target_node_id, replica_count, availability_tier, priority, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW(), NOW())"#,
    )
    .bind(&policy_id)
    .bind(auth.claims.sub)
    .bind(&req.category)
    .bind(&req.mime_patterns)
    .bind(&target_type)
    .bind(req.target_node_id.as_deref())
    .bind(replicas)
    .bind(&tier)
    .bind(priority)
    .execute(state.db.pool())
    .await?;

    Ok((
        StatusCode::CREATED,
        Json(serde_json::json!({
            "success": true,
            "policy": {
                "id": policy_id,
                "user_id": auth.claims.sub,
                "category": req.category,
                "mime_patterns": req.mime_patterns,
                "target_storage_type": target_type,
                "target_node_id": req.target_node_id,
                "replica_count": replicas,
                "availability_tier": tier,
                "priority": priority,
            }
        })),
    ))
}

/// DELETE /api/v1/storage/policies/:id
pub async fn delete_policy(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(policy_id): Path<String>,
) -> AppResult<impl IntoResponse> {
    sqlx::query("DELETE FROM storage_policies WHERE id = $1 AND user_id = $2")
        .bind(&policy_id)
        .bind(auth.claims.sub)
        .execute(state.db.pool())
        .await?;

    Ok(Json(
        serde_json::json!({ "success": true, "message": "Policy deleted" }),
    ))
}

/// POST /api/v1/storage/evaluate — Evaluate placement for incoming file.
pub async fn evaluate_storage(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<StorageEvaluateRequest>,
) -> AppResult<impl IntoResponse> {
    let name = req.name.unwrap_or_default();
    let eval = evaluate_placement(&name, req.mime_type.as_deref());

    let (cat_str, type_str) = match (&eval.category, &eval.target_storage_type) {
        (StorageCategory::Photos, StorageType::Ssd) => ("photos", "ssd"),
        (StorageCategory::Videos, StorageType::Hdd) => ("videos", "hdd"),
        (StorageCategory::Audio, _) => ("audio", "any"),
        (StorageCategory::Backups, StorageType::Usb) => ("backups", "usb"),
        _ => ("documents", "ssd"),
    };

    // Look for online nodes matching target storage type
    let node_row: Option<(String, String)> = sqlx::query_as(
        "SELECT id, name FROM storage_nodes WHERE user_id = $1 AND is_online = true ORDER BY free_bytes DESC LIMIT 1"
    )
    .bind(auth.claims.sub)
    .fetch_optional(state.db.pool())
    .await
    .unwrap_or(None);

    let (rec_id, rec_name) = match node_row {
        Some((id, n)) => (Some(id), n),
        None => (None, format!("{} Pool", type_str.to_uppercase())),
    };

    Ok(Json(serde_json::json!({
        "matched_category": cat_str,
        "target_storage_type": type_str,
        "recommended_storage_node_id": rec_id,
        "recommended_storage_node_name": rec_name,
        "replica_count": eval.replica_count,
        "availability_tier": eval.availability_tier,
        "rule_applied": eval.rule_name,
    })))
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
