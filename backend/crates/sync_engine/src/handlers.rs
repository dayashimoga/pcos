use crate::models::*;
use crate::service;
use axum::extract::{
    ws::{Message, WebSocket, WebSocketUpgrade},
    Path, Query, State,
};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use serde::Deserialize;
use uuid::Uuid;

#[derive(Debug, Deserialize)]
pub struct ChangesQuery {
    pub since: Option<String>,
    pub device_id: Option<Uuid>,
}

#[derive(Debug, Deserialize)]
pub struct WsAuthQuery {
    pub token: Option<String>,
}

pub async fn sync_websocket(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
    Query(auth): Query<WsAuthQuery>,
) -> Result<impl IntoResponse, AppError> {
    // Validate JWT from query param (WebSocket can't use Authorization header)
    let token = auth
        .token
        .ok_or_else(|| AppError::Unauthorized("Missing token query parameter".to_string()))?;
    let _claims = pcos_common::auth::jwt::validate_token(&token, &state.config.auth.jwt_secret)
        .map_err(|_| AppError::Unauthorized("Invalid token".to_string()))?;
    Ok(ws.on_upgrade(|socket| handle_sync_ws(socket, state)))
}

async fn handle_sync_ws(mut socket: WebSocket, _state: AppState) {
    while let Some(Ok(msg)) = socket.recv().await {
        match msg {
            Message::Text(text) => {
                if let Ok(sync_msg) = serde_json::from_str::<SyncMessage>(&text) {
                    let response = SyncMessage {
                        msg_type: "ack".to_string(),
                        payload: serde_json::json!({ "received": sync_msg.msg_type }),
                    };
                    if socket
                        .send(Message::Text(
                            serde_json::to_string(&response).unwrap_or_default(),
                        ))
                        .await
                        .is_err()
                    {
                        break;
                    }
                }
            }
            Message::Close(_) => break,
            _ => {}
        }
    }
    tracing::debug!("Sync WebSocket closed");
}

pub async fn sync_status(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(q): Query<ChangesQuery>,
) -> Result<impl IntoResponse, AppError> {
    let device_id = q.device_id.unwrap_or(Uuid::nil());
    let status = service::sync_status(state.db.pool(), auth.claims.sub, device_id).await?;
    Ok(Json(status))
}

pub async fn get_changes(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(q): Query<ChangesQuery>,
) -> Result<impl IntoResponse, AppError> {
    let since = q.since.and_then(|s| {
        chrono::DateTime::parse_from_rfc3339(&s)
            .ok()
            .map(|d| d.with_timezone(&chrono::Utc))
    });
    let changes = service::get_changes(state.db.pool(), auth.claims.sub, since).await?;
    Ok(Json(
        serde_json::json!({ "changes": changes, "total": changes.len() }),
    ))
}

pub async fn resolve_conflict(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<ResolveConflictRequest>,
) -> Result<impl IntoResponse, AppError> {
    service::resolve_conflict(state.db.pool(), auth.claims.sub, req).await?;
    Ok(Json(serde_json::json!({ "message": "Conflict resolved" })))
}

pub async fn list_sync_folders(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let folders = service::list_sync_folders(state.db.pool(), auth.claims.sub).await?;
    Ok(Json(serde_json::json!({ "folders": folders })))
}

pub async fn add_sync_folder(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<AddSyncFolderRequest>,
) -> Result<impl IntoResponse, AppError> {
    let folder = service::add_sync_folder(state.db.pool(), auth.claims.sub, req).await?;
    Ok((StatusCode::CREATED, Json(folder)))
}

pub async fn remove_sync_folder(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    service::remove_sync_folder(state.db.pool(), auth.claims.sub, id).await?;
    Ok(StatusCode::NO_CONTENT)
}
