//! PCOS Family Clouds & Multi-Tenant Isolation
//!
//! Provides Family / Household personal clouds with multi-tenant isolation,
//! per-member quotas, roles, and invitation management.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use chrono::{DateTime, Utc};
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::{AppError, AppResult};
use pcos_common::AppState;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct FamilyCloud {
    pub id: String,
    pub name: String,
    pub owner_id: Uuid,
    pub cloud_type: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct FamilyMember {
    pub id: String,
    pub cloud_id: String,
    pub user_id: Uuid,
    pub role: String,
    pub storage_quota_bytes: i64,
    pub used_bytes: i64,
    pub invite_code: Option<String>,
    pub joined_at: DateTime<Utc>,
}

#[derive(Deserialize)]
pub struct CreateCloudRequest {
    pub name: String,
    pub cloud_type: Option<String>,
}

#[derive(Serialize)]
pub struct CreateCloudResponse {
    pub success: bool,
    pub cloud: FamilyCloud,
}

#[derive(Deserialize)]
pub struct ListMembersQuery {
    pub cloud_id: Option<String>,
}

#[derive(Deserialize)]
pub struct InviteMemberRequest {
    pub cloud_id: String,
    pub user_id: Option<Uuid>,
    pub role: Option<String>,
    pub storage_quota_bytes: Option<i64>,
}

#[derive(Deserialize)]
pub struct UpdateRoleRequest {
    pub role: String,
}

#[derive(Deserialize)]
pub struct UpdateQuotaRequest {
    pub storage_quota_bytes: i64,
}

/// POST /api/v1/family/clouds — Create a family cloud.
pub async fn create_cloud(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<CreateCloudRequest>,
) -> AppResult<impl IntoResponse> {
    if req.name.trim().is_empty() {
        return Err(AppError::Validation("Cloud name is required".into()));
    }

    let cloud_id = format!("cld_{}", Uuid::new_v4());
    let member_id = format!("fmem_{}", Uuid::new_v4());
    let cloud_type = req.cloud_type.unwrap_or_else(|| "family".into());

    let cloud = sqlx::query_as::<_, FamilyCloud>(
        r#"INSERT INTO family_clouds (id, name, owner_id, cloud_type, created_at)
           VALUES ($1, $2, $3, $4, NOW())
           RETURNING *"#,
    )
    .bind(&cloud_id)
    .bind(req.name.trim())
    .bind(auth.claims.sub)
    .bind(&cloud_type)
    .fetch_one(state.db.pool())
    .await?;

    // Creator is owner with 50 GB default quota
    sqlx::query(
        r#"INSERT INTO family_members (id, cloud_id, user_id, role, storage_quota_bytes, used_bytes, invite_code, joined_at)
           VALUES ($1, $2, $3, 'owner', 53687091200, 0, NULL, NOW())"#,
    )
    .bind(&member_id)
    .bind(&cloud_id)
    .bind(auth.claims.sub)
    .execute(state.db.pool())
    .await?;

    Ok((StatusCode::CREATED, Json(CreateCloudResponse { success: true, cloud })))
}

/// GET /api/v1/family/clouds — List clouds owned by the user.
pub async fn list_clouds(
    State(state): State<AppState>,
    auth: AuthUser,
) -> AppResult<impl IntoResponse> {
    let clouds = sqlx::query_as::<_, FamilyCloud>(
        "SELECT * FROM family_clouds WHERE owner_id = $1 ORDER BY created_at DESC",
    )
    .bind(auth.claims.sub)
    .fetch_all(state.db.pool())
    .await?;

    Ok(Json(serde_json::json!({ "clouds": clouds })))
}

/// GET /api/v1/family/members — List family members.
pub async fn list_members(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(query): Query<ListMembersQuery>,
) -> AppResult<impl IntoResponse> {
    let members = if let Some(cloud_id) = query.cloud_id {
        // Enforce tenant isolation: caller must be an active member of this cloud
        let is_member: Option<(String,)> = sqlx::query_as(
            "SELECT id FROM family_members WHERE cloud_id = $1 AND user_id = $2",
        )
        .bind(&cloud_id)
        .bind(auth.claims.sub)
        .fetch_optional(state.db.pool())
        .await?;

        if is_member.is_none() {
            return Err(AppError::Forbidden(
                "Access denied: You are not a member of this family cloud".into(),
            ));
        }

        sqlx::query_as::<_, FamilyMember>(
            "SELECT * FROM family_members WHERE cloud_id = $1 ORDER BY joined_at ASC",
        )
        .bind(cloud_id)
        .fetch_all(state.db.pool())
        .await?
    } else {
        sqlx::query_as::<_, FamilyMember>(
            "SELECT * FROM family_members WHERE user_id = $1 ORDER BY joined_at ASC",
        )
        .bind(auth.claims.sub)
        .fetch_all(state.db.pool())
        .await?
    };

    Ok(Json(serde_json::json!({ "members": members })))
}

/// POST /api/v1/family/members/invite — Invite a new member.
pub async fn invite_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<InviteMemberRequest>,
) -> AppResult<impl IntoResponse> {
    // RBAC: Verify caller is owner or admin of the targeted family cloud
    let caller_member: Option<(String,)> = sqlx::query_as(
        "SELECT role FROM family_members WHERE cloud_id = $1 AND user_id = $2",
    )
    .bind(&req.cloud_id)
    .bind(auth.claims.sub)
    .fetch_optional(state.db.pool())
    .await?;

    match caller_member {
        Some((ref role,)) if role == "owner" || role == "admin" => {}
        _ => {
            return Err(AppError::Forbidden(
                "Only family cloud owners or administrators can invite members".into(),
            ));
        }
    }

    let member_id = format!("fmem_{}", Uuid::new_v4());
    let invite_code = format!("fam_inv_{}", Uuid::new_v4().simple().to_string()[..12].to_string());
    let target_user_id = req.user_id.unwrap_or_else(Uuid::new_v4);
    let role = req.role.unwrap_or_else(|| "member".into());
    let quota = req.storage_quota_bytes.unwrap_or(21474836480); // 20 GB default

    let member = sqlx::query_as::<_, FamilyMember>(
        r#"INSERT INTO family_members (id, cloud_id, user_id, role, storage_quota_bytes, used_bytes, invite_code, joined_at)
           VALUES ($1, $2, $3, $4, $5, 0, $6, NOW())
           RETURNING *"#,
    )
    .bind(&member_id)
    .bind(&req.cloud_id)
    .bind(target_user_id)
    .bind(&role)
    .bind(quota)
    .bind(&invite_code)
    .fetch_one(state.db.pool())
    .await?;

    Ok(Json(serde_json::json!({
        "success": true,
        "member": member,
    })))
}

/// PUT /api/v1/family/members/:id/role — Update member role.
pub async fn update_member_role(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(member_id): Path<String>,
    Json(req): Json<UpdateRoleRequest>,
) -> AppResult<impl IntoResponse> {
    let target = sqlx::query_as::<_, (String, Uuid, String)>(
        "SELECT cloud_id, user_id, role FROM family_members WHERE id = $1",
    )
    .bind(&member_id)
    .fetch_optional(state.db.pool())
    .await?
    .ok_or_else(|| AppError::NotFound("Family member not found".into()))?;

    // RBAC: Caller must be owner of the cloud
    let caller_role: Option<(String,)> = sqlx::query_as(
        "SELECT role FROM family_members WHERE cloud_id = $1 AND user_id = $2",
    )
    .bind(&target.0)
    .bind(auth.claims.sub)
    .fetch_optional(state.db.pool())
    .await?;

    if !matches!(caller_role, Some((ref r,)) if r == "owner") {
        return Err(AppError::Forbidden(
            "Only the family cloud owner can modify member roles".into(),
        ));
    }

    sqlx::query("UPDATE family_members SET role = $1 WHERE id = $2")
        .bind(&req.role)
        .bind(&member_id)
        .execute(state.db.pool())
        .await?;

    Ok(Json(serde_json::json!({ "success": true, "role": req.role })))
}

/// PUT /api/v1/family/members/:id/quota — Update member quota.
pub async fn update_member_quota(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(member_id): Path<String>,
    Json(req): Json<UpdateQuotaRequest>,
) -> AppResult<impl IntoResponse> {
    let target = sqlx::query_as::<_, (String, Uuid)>(
        "SELECT cloud_id, user_id FROM family_members WHERE id = $1",
    )
    .bind(&member_id)
    .fetch_optional(state.db.pool())
    .await?
    .ok_or_else(|| AppError::NotFound("Family member not found".into()))?;

    // RBAC: Caller must be owner or admin
    let caller_role: Option<(String,)> = sqlx::query_as(
        "SELECT role FROM family_members WHERE cloud_id = $1 AND user_id = $2",
    )
    .bind(&target.0)
    .bind(auth.claims.sub)
    .fetch_optional(state.db.pool())
    .await?;

    match caller_role {
        Some((ref r,)) if r == "owner" || r == "admin" => {}
        _ => {
            return Err(AppError::Forbidden(
                "Only family cloud owners or administrators can modify storage quotas".into(),
            ));
        }
    }

    sqlx::query("UPDATE family_members SET storage_quota_bytes = $1 WHERE id = $2")
        .bind(req.storage_quota_bytes)
        .bind(&member_id)
        .execute(state.db.pool())
        .await?;

    Ok(Json(serde_json::json!({
        "success": true,
        "storage_quota_bytes": req.storage_quota_bytes,
    })))
}

/// DELETE /api/v1/family/members/:id — Remove a member from the cloud.
pub async fn delete_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(member_id): Path<String>,
) -> AppResult<impl IntoResponse> {
    let target = sqlx::query_as::<_, (String, Uuid, String)>(
        "SELECT cloud_id, user_id, role FROM family_members WHERE id = $1",
    )
    .bind(&member_id)
    .fetch_optional(state.db.pool())
    .await?
    .ok_or_else(|| AppError::NotFound("Family member not found".into()))?;

    let is_self = target.1 == auth.claims.sub;

    if !is_self {
        // RBAC: Caller must be owner or admin
        let caller_role: Option<(String,)> = sqlx::query_as(
            "SELECT role FROM family_members WHERE cloud_id = $1 AND user_id = $2",
        )
        .bind(&target.0)
        .bind(auth.claims.sub)
        .fetch_optional(state.db.pool())
        .await?;

        match caller_role {
            Some((ref r,)) if r == "owner" || (r == "admin" && target.2 != "owner") => {}
            _ => {
                return Err(AppError::Forbidden(
                    "Insufficient permissions to remove this family member".into(),
                ));
            }
        }
    }

    sqlx::query("DELETE FROM family_members WHERE id = $1")
        .bind(&member_id)
        .execute(state.db.pool())
        .await?;

    Ok(Json(serde_json::json!({ "success": true, "message": "Member removed" })))
}
