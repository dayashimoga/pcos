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
    headers: axum::http::HeaderMap,
    State(state): State<AppState>,
    Query(auth): Query<WsAuthQuery>,
) -> Result<impl IntoResponse, AppError> {
    // Validate JWT: prefer Authorization header or Sec-WebSocket-Protocol to prevent URL query leak
    let token = if let Some(auth_hdr) = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
    {
        if let Some(bearer) = auth_hdr.strip_prefix("Bearer ") {
            Some(bearer.trim().to_string())
        } else {
            Some(auth_hdr.trim().to_string())
        }
    } else if let Some(proto) = headers
        .get("sec-websocket-protocol")
        .and_then(|v| v.to_str().ok())
    {
        let parts: Vec<&str> = proto.split(',').map(|s| s.trim()).collect();
        if parts.len() >= 2 {
            Some(parts[1].to_string())
        } else if !parts.is_empty() && parts[0].len() > 20 {
            Some(parts[0].to_string())
        } else {
            None
        }
    } else {
        auth.token
    };

    let token = token.ok_or_else(|| {
        AppError::Unauthorized(
            "Missing authentication token via Authorization header, subprotocol, or token parameter"
                .to_string(),
        )
    })?;

    let claims = pcos_common::auth::jwt::validate_token(&token, &state.config.auth.jwt_secret)
        .map_err(|_| {
            AppError::Unauthorized("Invalid or expired authentication token".to_string())
        })?;

    let user_id = claims.claims.sub;
    Ok(ws.on_upgrade(move |socket| handle_sync_ws(socket, state, user_id)))
}

async fn handle_sync_ws(mut socket: WebSocket, state: AppState, user_id: Uuid) {
    while let Some(Ok(msg)) = socket.recv().await {
        match msg {
            Message::Text(text) => {
                if let Ok(sync_msg) = serde_json::from_str::<SyncMessage>(&text) {
                    let pool = state.db.pool();
                    let response = match sync_msg.msg_type.as_str() {
                        "ping" => SyncMessage {
                            msg_type: "pong".to_string(),
                            payload: serde_json::json!({ "timestamp": chrono::Utc::now().to_rfc3339() }),
                        },
                        "get_changes" => {
                            let since = sync_msg
                                .payload
                                .get("since")
                                .and_then(|v| v.as_str())
                                .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                                .map(|d| d.with_timezone(&chrono::Utc));
                            match service::get_changes(pool, user_id, since).await {
                                Ok(changes) => SyncMessage {
                                    msg_type: "changes".to_string(),
                                    payload: serde_json::json!({ "changes": changes, "total": changes.len() }),
                                },
                                Err(e) => SyncMessage {
                                    msg_type: "error".to_string(),
                                    payload: serde_json::json!({ "error": e.to_string() }),
                                },
                            }
                        }
                        "resolve_conflict" => {
                            if let Ok(req) =
                                serde_json::from_value::<ResolveConflictRequest>(sync_msg.payload)
                            {
                                match service::resolve_conflict(pool, user_id, req).await {
                                    Ok(_) => SyncMessage {
                                        msg_type: "conflict_resolved".to_string(),
                                        payload: serde_json::json!({ "status": "resolved" }),
                                    },
                                    Err(e) => SyncMessage {
                                        msg_type: "error".to_string(),
                                        payload: serde_json::json!({ "error": e.to_string() }),
                                    },
                                }
                            } else {
                                SyncMessage {
                                    msg_type: "error".to_string(),
                                    payload: serde_json::json!({ "error": "Invalid resolve_conflict payload" }),
                                }
                            }
                        }
                        "status" => {
                            let device_id = sync_msg
                                .payload
                                .get("device_id")
                                .and_then(|v| v.as_str())
                                .and_then(|s| Uuid::parse_str(s).ok())
                                .unwrap_or_else(Uuid::nil);
                            match service::sync_status(pool, user_id, device_id).await {
                                Ok(status) => SyncMessage {
                                    msg_type: "status_report".to_string(),
                                    payload: serde_json::to_value(status).unwrap_or_default(),
                                },
                                Err(e) => SyncMessage {
                                    msg_type: "error".to_string(),
                                    payload: serde_json::json!({ "error": e.to_string() }),
                                },
                            }
                        }
                        _ => SyncMessage {
                            msg_type: "ack".to_string(),
                            payload: serde_json::json!({ "received": sync_msg.msg_type, "status": "processed" }),
                        },
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
    tracing::debug!(user_id = %user_id, "Sync WebSocket closed");
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
