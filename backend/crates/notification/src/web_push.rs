//! Web Push notification service.
//!
//! Manages browser push subscriptions and sends push notifications
//! via the Web Push protocol (RFC 8030).

use chrono::{DateTime, Utc};
use pcos_common::error::{AppError, AppResult};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

#[derive(Debug, Clone, sqlx::FromRow, Serialize)]
pub struct PushSubscription {
    pub id: Uuid,
    pub user_id: Uuid,
    pub endpoint: String,
    pub p256dh_key: String,
    pub auth_key: String,
    pub user_agent: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct SubscribeRequest {
    pub endpoint: String,
    pub keys: PushKeys,
}

#[derive(Debug, Deserialize)]
pub struct PushKeys {
    pub p256dh: String,
    pub auth: String,
}

#[derive(Debug, Serialize)]
pub struct PushPayload {
    pub title: String,
    pub body: String,
    pub icon: Option<String>,
    pub url: Option<String>,
    pub tag: Option<String>,
}

/// Subscribe a browser to push notifications.
pub async fn subscribe(
    pool: &PgPool,
    user_id: Uuid,
    req: SubscribeRequest,
    user_agent: Option<String>,
) -> AppResult<PushSubscription> {
    // Upsert — update existing subscription for same endpoint
    let sub = sqlx::query_as::<_, PushSubscription>(
        "INSERT INTO push_subscriptions (id, user_id, endpoint, p256dh_key, auth_key, user_agent, created_at) \
         VALUES ($1, $2, $3, $4, $5, $6, NOW()) \
         ON CONFLICT (endpoint) DO UPDATE SET p256dh_key = $4, auth_key = $5, user_agent = $6 \
         RETURNING *"
    )
    .bind(Uuid::new_v4())
    .bind(user_id)
    .bind(&req.endpoint)
    .bind(&req.keys.p256dh)
    .bind(&req.keys.auth)
    .bind(&user_agent)
    .fetch_one(pool).await?;

    tracing::info!(user_id = %user_id, endpoint = %req.endpoint, "Push subscription registered");
    Ok(sub)
}

/// Remove a push subscription.
pub async fn unsubscribe(pool: &PgPool, user_id: Uuid, endpoint: &str) -> AppResult<()> {
    sqlx::query("DELETE FROM push_subscriptions WHERE user_id = $1 AND endpoint = $2")
        .bind(user_id)
        .bind(endpoint)
        .execute(pool)
        .await?;
    Ok(())
}

/// List all push subscriptions for a user.
pub async fn list_subscriptions(pool: &PgPool, user_id: Uuid) -> AppResult<Vec<PushSubscription>> {
    Ok(sqlx::query_as::<_, PushSubscription>(
        "SELECT * FROM push_subscriptions WHERE user_id = $1 ORDER BY created_at DESC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?)
}

/// Send a push notification to all of a user's subscribed browsers.
/// Uses the Web Push protocol — HTTP POST to the subscription endpoint.
pub async fn send_push(pool: &PgPool, user_id: Uuid, payload: &PushPayload) -> AppResult<u32> {
    let subs = list_subscriptions(pool, user_id).await?;
    let body = serde_json::to_string(payload).unwrap_or_default();
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .build()
        .map_err(|e| AppError::Internal(format!("HTTP client error: {e}")))?;

    let mut sent = 0u32;
    for sub in &subs {
        match client
            .post(&sub.endpoint)
            .header("Content-Type", "application/json")
            .header("TTL", "86400")
            .body(body.clone())
            .send()
            .await
        {
            Ok(resp) if resp.status().is_success() || resp.status().as_u16() == 201 => {
                sent += 1;
            }
            Ok(resp) if resp.status().as_u16() == 410 => {
                // Subscription expired — clean up
                let _ = sqlx::query("DELETE FROM push_subscriptions WHERE id = $1")
                    .bind(sub.id)
                    .execute(pool)
                    .await;
                tracing::info!(sub_id = %sub.id, "Removed expired push subscription");
            }
            Ok(resp) => {
                tracing::warn!(sub_id = %sub.id, status = %resp.status(), "Push notification delivery failed");
            }
            Err(e) => {
                tracing::warn!(sub_id = %sub.id, error = %e, "Push notification send error");
            }
        }
    }

    tracing::info!(user_id = %user_id, sent = sent, total = subs.len(), "Push notifications sent");
    Ok(sent)
}
