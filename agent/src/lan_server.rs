//! PCOS Agent Embedded LAN HTTP Server
//!
//! Provides direct, line-rate local network HTTP/1.1 transfers without routing through
//! Cloudflare relay workers. Includes HTTP Range / 206 Partial Content streaming and CORS.

use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::Path;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

use crate::fs_handler::FsHandler;

pub struct LanServerConfig {
    pub device_id: String,
    pub auth_token: String,
    pub preferred_port: u16,
}

pub struct LanServer {
    config: Arc<LanServerConfig>,
}

impl LanServer {
    pub fn new(device_id: String, auth_token: String, preferred_port: u16) -> Self {
        Self {
            config: Arc::new(LanServerConfig {
                device_id,
                auth_token,
                preferred_port,
            }),
        }
    }

    /// Start listening for direct LAN requests on an available port.
    /// Returns the actual port bound.
    pub async fn start(
        &self,
    ) -> Result<u16, Box<dyn std::error::Error + Send + Sync>> {
        let mut port = self.config.preferred_port;
        let mut listener: Option<TcpListener> = None;

        for p in port..port + 20 {
            let addr = format!("0.0.0.0:{}", p);
            match TcpListener::bind(&addr).await {
                Ok(l) => {
                    port = p;
                    listener = Some(l);
                    break;
                }
                Err(_) => continue,
            }
        }

        let listener = match listener {
            Some(l) => l,
            None => {
                return Err(format!(
                    "Failed to bind LAN server to ports {}-{}",
                    self.config.preferred_port,
                    self.config.preferred_port + 20
                )
                .into());
            }
        };

        tracing::info!(port = port, "Direct LAN Data Plane HTTP Server listening");

        let config = self.config.clone();
        tokio::spawn(async move {
            loop {
                match listener.accept().await {
                    Ok((stream, remote_addr)) => {
                        let cfg = config.clone();
                        tokio::spawn(async move {
                            if let Err(e) = handle_connection(stream, remote_addr, cfg).await {
                                tracing::debug!(error = %e, "LAN connection error");
                            }
                        });
                    }
                    Err(e) => {
                        tracing::warn!(error = %e, "LAN server accept error");
                        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
                    }
                }
            }
        });

        Ok(port)
    }
}

async fn handle_connection(
    mut stream: TcpStream,
    _remote_addr: SocketAddr,
    config: Arc<LanServerConfig>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut buf = vec![0u8; 16384];
    let bytes_read = stream.read(&mut buf).await?;
    if bytes_read == 0 {
        return Ok(());
    }

    let req_str = String::from_utf8_lossy(&buf[..bytes_read]);
    let mut lines = req_str.lines();
    let request_line = match lines.next() {
        Some(l) => l,
        None => return Ok(()),
    };

    let parts: Vec<&str> = request_line.split_whitespace().collect();
    if parts.len() < 2 {
        return Ok(());
    }

    let method = parts[0];
    let full_path = parts[1];

    let mut headers = HashMap::new();
    for line in lines {
        if line.is_empty() || line == "\r" {
            break;
        }
        if let Some((k, v)) = line.split_once(':') {
            headers.insert(k.trim().to_lowercase(), v.trim().to_string());
        }
    }

    // Handle CORS preflight
    if method == "OPTIONS" {
        let resp = "HTTP/1.1 204 No Content\r\n\
                    Access-Control-Allow-Origin: *\r\n\
                    Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\n\
                    Access-Control-Allow-Headers: Authorization, Content-Type, Range\r\n\
                    Access-Control-Max-Age: 86400\r\n\
                    Content-Length: 0\r\n\r\n";
        stream.write_all(resp.as_bytes()).await?;
        return Ok(());
    }

    // Parse URL path and query parameters
    let (path_only, query_params) = parse_query(full_path);

    // Unauthenticated Ping
    if path_only == "/api/v1/lan/ping" {
        let host = hostname::get()
            .map(|h| h.to_string_lossy().to_string())
            .unwrap_or_else(|_| "unknown".to_string());
        let body = serde_json::json!({
            "status": "pong",
            "device_id": config.device_id,
            "hostname": host,
        })
        .to_string();
        send_json_response(&mut stream, 200, &body).await?;
        return Ok(());
    }

    // Authenticate token (Bearer header or query param)
    let auth_header = headers.get("authorization").map(|s| s.as_str()).unwrap_or("");
    let mut token = if auth_header.starts_with("Bearer ") {
        &auth_header[7..]
    } else {
        query_params.get("token").map(|s| s.as_str()).unwrap_or("")
    };
    token = token.trim();

    if !config.auth_token.is_empty() && (token.is_empty() || token != config.auth_token) {
        let body = serde_json::json!({ "error": "Unauthorized direct LAN access" }).to_string();
        send_json_response(&mut stream, 401, &body).await?;
        return Ok(());
    }

    // ─── Direct Filesystem Operations ───

    if path_only == "/api/v1/lan/fs/list" && method == "GET" {
        let storage_path = query_params.get("storage_path").map(|s| s.as_str()).unwrap_or(".");
        let rel_path = query_params.get("path").map(|s| s.as_str()).unwrap_or("");
        match FsHandler::list_dir(Path::new(storage_path), rel_path) {
            Ok(result) => {
                let body = serde_json::to_string(&result).unwrap_or_default();
                send_json_response(&mut stream, 200, &body).await?;
            }
            Err(e) => {
                let body = serde_json::json!({ "error": e.to_string() }).to_string();
                send_json_response(&mut stream, 400, &body).await?;
            }
        }
        return Ok(());
    }

    if path_only == "/api/v1/lan/fs/stat" && method == "GET" {
        let storage_path = query_params.get("storage_path").map(|s| s.as_str()).unwrap_or(".");
        let rel_path = query_params.get("path").map(|s| s.as_str()).unwrap_or("");
        match FsHandler::stat(Path::new(storage_path), rel_path) {
            Ok(meta) => {
                let body = serde_json::json!(meta).to_string();
                send_json_response(&mut stream, 200, &body).await?;
            }
            Err(e) => {
                let body = serde_json::json!({ "error": e.to_string() }).to_string();
                send_json_response(&mut stream, 404, &body).await?;
            }
        }
        return Ok(());
    }

    if path_only == "/api/v1/lan/fs/read" && method == "GET" {
        let storage_path = query_params.get("storage_path").map(|s| s.as_str()).unwrap_or(".");
        let rel_path = query_params.get("path").map(|s| s.as_str()).unwrap_or("");

        let canonical_root = match Path::new(storage_path).canonicalize() {
            Ok(p) => p,
            Err(_) => {
                send_json_response(&mut stream, 404, r#"{"error":"Storage root not found"}"#).await?;
                return Ok(());
            }
        };

        let target_path = match FsHandler::safe_resolve(&canonical_root, rel_path) {
            Ok(p) => p,
            Err(e) => {
                let body = serde_json::json!({ "error": e.to_string() }).to_string();
                send_json_response(&mut stream, 403, &body).await?;
                return Ok(());
            }
        };

        if !target_path.is_file() {
            send_json_response(&mut stream, 404, r#"{"error":"File not found"}"#).await?;
            return Ok(());
        }

        let total_size = match target_path.metadata() {
            Ok(m) => m.len(),
            Err(e) => {
                let body = serde_json::json!({ "error": e.to_string() }).to_string();
                send_json_response(&mut stream, 500, &body).await?;
                return Ok(());
            }
        };

        let mime = detect_mime(&target_path);
        let range_header = headers.get("range").map(|s| s.as_str());

        if let Some(range) = range_header {
            if let Some((start, end)) = parse_range(range, total_size) {
                let content_len = end - start + 1;
                let header = format!(
                    "HTTP/1.1 206 Partial Content\r\n\
                     Content-Type: {}\r\n\
                     Content-Length: {}\r\n\
                     Content-Range: bytes {}-{}/{}\r\n\
                     Accept-Ranges: bytes\r\n\
                     Access-Control-Allow-Origin: *\r\n\
                     Access-Control-Allow-Headers: Authorization, Content-Type, Range\r\n\r\n",
                    mime, content_len, start, end, total_size
                );
                stream.write_all(header.as_bytes()).await?;

                // Stream the range slice directly
                if let Ok(mut file) = tokio::fs::File::open(&target_path).await {
                    use std::io::SeekFrom;
                    use tokio::io::AsyncSeekExt;
                    let _ = file.seek(SeekFrom::Start(start)).await;
                    let mut limited = file.take(content_len);
                    let _ = tokio::io::copy(&mut limited, &mut stream).await;
                }
                return Ok(());
            }
        }

        // Full file stream
        let header = format!(
            "HTTP/1.1 200 OK\r\n\
             Content-Type: {}\r\n\
             Content-Length: {}\r\n\
             Accept-Ranges: bytes\r\n\
             Access-Control-Allow-Origin: *\r\n\
             Access-Control-Allow-Headers: Authorization, Content-Type, Range\r\n\r\n",
            mime, total_size
        );
        stream.write_all(header.as_bytes()).await?;

        if let Ok(mut file) = tokio::fs::File::open(&target_path).await {
            let _ = tokio::io::copy(&mut file, &mut stream).await;
        }
        return Ok(());
    }

    send_json_response(&mut stream, 404, r#"{"error":"Endpoint not found"}"#).await?;
    Ok(())
}

fn parse_query(full_path: &str) -> (&str, HashMap<String, String>) {
    let mut map = HashMap::new();
    let parts: Vec<&str> = full_path.splitn(2, '?').collect();
    let path = parts[0];
    if parts.len() > 1 {
        for pair in parts[1].split('&') {
            if let Some((k, v)) = pair.split_once('=') {
                let decoded_k = percent_decode(k);
                let decoded_v = percent_decode(v);
                map.insert(decoded_k, decoded_v);
            }
        }
    }
    (path, map)
}

fn percent_decode(s: &str) -> String {
    let mut bytes = Vec::new();
    let mut chars = s.as_bytes().iter().copied();
    while let Some(b) = chars.next() {
        if b == b'%' {
            if let (Some(h1), Some(h2)) = (chars.next(), chars.next()) {
                if let Ok(hex_byte) = u8::from_str_radix(
                    &format!("{}{}", h1 as char, h2 as char),
                    16,
                ) {
                    bytes.push(hex_byte);
                    continue;
                }
            }
        } else if b == b'+' {
            bytes.push(b' ');
            continue;
        }
        bytes.push(b);
    }
    String::from_utf8_lossy(&bytes).to_string()
}

fn parse_range(range_header: &str, total_size: u64) -> Option<(u64, u64)> {
    if !range_header.starts_with("bytes=") {
        return None;
    }
    let parts: Vec<&str> = range_header[6..].split('-').collect();
    if parts.is_empty() {
        return None;
    }

    let start = parts[0].parse::<u64>().ok()?;
    let end = if parts.len() > 1 && !parts[1].is_empty() {
        parts[1].parse::<u64>().ok()?.min(total_size.saturating_sub(1))
    } else {
        total_size.saturating_sub(1)
    };

    if start <= end && start < total_size {
        Some((start, end))
    } else {
        None
    }
}

fn detect_mime(path: &Path) -> &'static str {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();
    match ext.as_str() {
        "mp4" => "video/mp4",
        "webm" => "video/webm",
        "mkv" => "video/x-matroska",
        "mp3" => "audio/mpeg",
        "flac" => "audio/flac",
        "wav" => "audio/wav",
        "jpg" | "jpeg" => "image/jpeg",
        "png" => "image/png",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "svg" => "image/svg+xml",
        "pdf" => "application/pdf",
        "json" => "application/json",
        "txt" | "md" | "rs" | "dart" | "ts" => "text/plain; charset=utf-8",
        _ => "application/octet-stream",
    }
}

async fn send_json_response(
    stream: &mut TcpStream,
    status: u16,
    body: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let status_text = match status {
        200 => "OK",
        201 => "Created",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        500 => "Internal Server Error",
        _ => "OK",
    };

    let resp = format!(
        "HTTP/1.1 {} {}\r\n\
         Content-Type: application/json\r\n\
         Content-Length: {}\r\n\
         Access-Control-Allow-Origin: *\r\n\
         Access-Control-Allow-Headers: Authorization, Content-Type, Range\r\n\r\n{}",
        status,
        status_text,
        body.len(),
        body
    );

    stream.write_all(resp.as_bytes()).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_range_valid() {
        assert_eq!(parse_range("bytes=0-100", 1000), Some((0, 100)));
        assert_eq!(parse_range("bytes=500-", 1000), Some((500, 999)));
        assert_eq!(parse_range("bytes=0-2000", 1000), Some((0, 999)));
    }

    #[test]
    fn test_parse_range_invalid() {
        assert_eq!(parse_range("invalid", 1000), None);
        assert_eq!(parse_range("bytes=1500-2000", 1000), None);
    }

    #[test]
    fn test_query_parsing() {
        let (path, map) = parse_query("/api/v1/lan/fs/read?storage_path=C%3A%5CUsers&path=file.txt");
        assert_eq!(path, "/api/v1/lan/fs/read");
        assert_eq!(map.get("storage_path"), Some(&"C:\\Users".to_string()));
        assert_eq!(map.get("path"), Some(&"file.txt".to_string()));
    }

    #[tokio::test]
    async fn test_lan_server_real_http_e2e() {
        let test_dir = std::env::temp_dir().join(format!("pcos_lan_test_{}", uuid::Uuid::new_v4()));
        tokio::fs::create_dir_all(&test_dir).await.unwrap();

        let test_file = test_dir.join("stream_test.txt");
        tokio::fs::write(&test_file, b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ").await.unwrap();

        let token = "test_lan_token_secret_12345".to_string();
        let server = LanServer::new("test_dev_01".to_string(), token.clone(), 18080);
        let port = server.start().await.expect("Failed to start LAN server");

        let client = reqwest::Client::new();

        // 1. Test unauthenticated ping
        let ping_url = format!("http://127.0.0.1:{}/api/v1/lan/ping", port);
        let resp = client.get(&ping_url).send().await.expect("Ping failed");
        assert_eq!(resp.status(), 200);
        let body: serde_json::Value = resp.json().await.expect("Ping JSON failed");
        assert_eq!(body["status"], "pong");
        assert_eq!(body["device_id"], "test_dev_01");

        // 2. Test unauthorized access without token
        let list_url = format!(
            "http://127.0.0.1:{}/api/v1/lan/fs/list?storage_path={}",
            port,
            test_dir.display()
        );
        let unauth_resp = client.get(&list_url).send().await.expect("Unauth req failed");
        assert_eq!(unauth_resp.status(), 401);

        // 3. Test directory listing with Bearer token
        let auth_resp = client
            .get(&list_url)
            .bearer_auth(&token)
            .send()
            .await
            .expect("Auth list failed");
        assert_eq!(auth_resp.status(), 200);
        let list_json: serde_json::Value = auth_resp.json().await.expect("List JSON failed");
        let entries = list_json["entries"].as_array().expect("Entries array");
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0]["name"], "stream_test.txt");

        // 4. Test HTTP Range 206 streaming with query token
        let read_url = format!(
            "http://127.0.0.1:{}/api/v1/lan/fs/read?storage_path={}&path=stream_test.txt&token={}",
            port,
            test_dir.display(),
            token
        );
        let range_resp = client
            .get(&read_url)
            .header("Range", "bytes=0-9")
            .send()
            .await
            .expect("Range req failed");
        assert_eq!(range_resp.status(), 206);
        assert!(range_resp.headers().get("content-range").is_some());
        let range_bytes = range_resp.bytes().await.expect("Range bytes failed");
        assert_eq!(&range_bytes[..], b"0123456789");

        // Clean up test directory
        let _ = tokio::fs::remove_dir_all(&test_dir).await;
    }
}

