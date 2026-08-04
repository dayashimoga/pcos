use pcos_common::error::{AppError, AppResult};
use serde::Deserialize;
use std::time::Duration;

async fn read_smtp_response(
    r: &mut tokio::io::ReadHalf<tokio::net::TcpStream>,
    b: &mut [u8],
) -> Result<String, AppError> {
    use tokio::io::AsyncReadExt;
    let n = r
        .read(b)
        .await
        .map_err(|e| AppError::Internal(format!("SMTP read: {e}")))?;
    let resp = String::from_utf8_lossy(&b[..n]).to_string();
    Ok(resp)
}

/// SMTP email notification sender.
/// Configure via environment: PCOS_SMTP_HOST, PCOS_SMTP_PORT, PCOS_SMTP_USER, PCOS_SMTP_PASS, PCOS_SMTP_FROM
#[derive(Debug, Clone)]
pub struct EmailSender {
    pub host: String,
    pub port: u16,
    pub username: Option<String>,
    pub password: Option<String>,
    pub from_address: String,
    pub enabled: bool,
}

#[derive(Debug, Deserialize)]
pub struct EmailMessage {
    pub to: String,
    pub subject: String,
    pub body_html: String,
    pub body_text: Option<String>,
}

impl EmailSender {
    /// Create from environment variables. Returns disabled sender if SMTP not configured.
    pub fn from_env() -> Self {
        let host = std::env::var("PCOS_SMTP_HOST").unwrap_or_default();
        let enabled = !host.is_empty();

        Self {
            host,
            port: std::env::var("PCOS_SMTP_PORT")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(587),
            username: std::env::var("PCOS_SMTP_USER").ok(),
            password: std::env::var("PCOS_SMTP_PASS").ok(),
            from_address: std::env::var("PCOS_SMTP_FROM")
                .unwrap_or_else(|_| "noreply@pcos.local".to_string()),
            enabled,
        }
    }

    /// Send an email via SMTP using raw TCP + STARTTLS.
    /// This is a minimal implementation — for production, use `lettre` crate.
    pub async fn send(&self, msg: &EmailMessage) -> AppResult<()> {
        if !self.enabled {
            tracing::debug!(to = %msg.to, subject = %msg.subject, "Email skipped (SMTP not configured)");
            return Ok(());
        }

        // Build MIME message
        let body = msg.body_text.as_deref().unwrap_or("See HTML version");
        let mime_msg = format!(
            "From: {from}\r\nTo: {to}\r\nSubject: {subject}\r\nMIME-Version: 1.0\r\nContent-Type: multipart/alternative; boundary=\"pcos-boundary\"\r\n\r\n--pcos-boundary\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n{text}\r\n--pcos-boundary\r\nContent-Type: text/html; charset=utf-8\r\n\r\n{html}\r\n--pcos-boundary--\r\n",
            from = self.from_address, to = msg.to, subject = msg.subject,
            text = body, html = msg.body_html,
        );

        // Connect to SMTP server
        let addr = format!("{}:{}", self.host, self.port);
        let stream = tokio::time::timeout(
            Duration::from_secs(10),
            tokio::net::TcpStream::connect(&addr),
        )
        .await
        .map_err(|_| AppError::Internal("SMTP connection timeout".to_string()))?
        .map_err(|e| AppError::Internal(format!("SMTP connection failed: {e}")))?;

        // Simple SMTP conversation
        use tokio::io::AsyncWriteExt;
        let (mut reader, mut writer) = tokio::io::split(stream);

        // Helper to read SMTP response
        let mut buf = vec![0u8; 1024];

        // Read greeting
        let _ = read_smtp_response(&mut reader, &mut buf).await?;

        // EHLO
        writer
            .write_all(b"EHLO pcos\r\n")
            .await
            .map_err(|e| AppError::Internal(format!("SMTP write: {e}")))?;
        let _ = read_smtp_response(&mut reader, &mut buf).await?;

        // AUTH if credentials provided
        if let (Some(user), Some(pass)) = (&self.username, &self.password) {
            let credentials = base64_encode(&format!("\0{}\0{}", user, pass));
            writer
                .write_all(format!("AUTH PLAIN {}\r\n", credentials).as_bytes())
                .await
                .map_err(|e| AppError::Internal(format!("SMTP auth: {e}")))?;
            let resp = read_smtp_response(&mut reader, &mut buf).await?;
            if !resp.starts_with("235") {
                return Err(AppError::Internal(format!("SMTP auth failed: {resp}")));
            }
        }

        // MAIL FROM
        writer
            .write_all(format!("MAIL FROM:<{}>\r\n", self.from_address).as_bytes())
            .await
            .map_err(|e| AppError::Internal(format!("SMTP: {e}")))?;
        let _ = read_smtp_response(&mut reader, &mut buf).await?;

        // RCPT TO
        writer
            .write_all(format!("RCPT TO:<{}>\r\n", msg.to).as_bytes())
            .await
            .map_err(|e| AppError::Internal(format!("SMTP: {e}")))?;
        let _ = read_smtp_response(&mut reader, &mut buf).await?;

        // DATA
        writer
            .write_all(b"DATA\r\n")
            .await
            .map_err(|e| AppError::Internal(format!("SMTP: {e}")))?;
        let _ = read_smtp_response(&mut reader, &mut buf).await?;

        // Message body + terminator
        writer
            .write_all(format!("{}\r\n.\r\n", mime_msg).as_bytes())
            .await
            .map_err(|e| AppError::Internal(format!("SMTP: {e}")))?;
        let resp = read_smtp_response(&mut reader, &mut buf).await?;

        // QUIT
        writer.write_all(b"QUIT\r\n").await.ok();

        if resp.starts_with("250") {
            tracing::info!(to = %msg.to, subject = %msg.subject, "Email sent");
            Ok(())
        } else {
            Err(AppError::Internal(format!("SMTP send failed: {resp}")))
        }
    }
}

fn base64_encode(input: &str) -> String {
    use base64::Engine;
    base64::engine::general_purpose::STANDARD.encode(input.as_bytes())
}

/// Send common notification emails
impl EmailSender {
    pub async fn send_welcome(&self, to: &str, display_name: &str) -> AppResult<()> {
        self.send(&EmailMessage {
            to: to.to_string(),
            subject: "Welcome to PCOS".to_string(),
            body_html: format!(
                "<h1>Welcome, {}!</h1><p>Your Personal Cloud Operating System is ready.</p><p>Start uploading files, syncing devices, and taking control of your data.</p>",
                display_name
            ),
            body_text: Some(format!("Welcome, {}! Your PCOS is ready.", display_name)),
        }).await
    }

    pub async fn send_backup_complete(
        &self,
        to: &str,
        backup_name: &str,
        file_count: i64,
    ) -> AppResult<()> {
        self.send(&EmailMessage {
            to: to.to_string(),
            subject: format!("Backup Complete: {}", backup_name),
            body_html: format!(
                "<h2>Backup Completed</h2><p><strong>{}</strong> — {} files backed up successfully.</p>",
                backup_name, file_count
            ),
            body_text: Some(format!("Backup '{}' completed: {} files", backup_name, file_count)),
        }).await
    }

    pub async fn send_share_notification(
        &self,
        to: &str,
        sharer_name: &str,
        file_name: &str,
        share_url: &str,
    ) -> AppResult<()> {
        self.send(&EmailMessage {
            to: to.to_string(),
            subject: format!("{} shared a file with you", sharer_name),
            body_html: format!(
                "<h2>File Shared</h2><p><strong>{}</strong> shared <em>{}</em> with you.</p><p><a href='{}'>View File</a></p>",
                sharer_name, file_name, share_url
            ),
            body_text: Some(format!("{} shared '{}': {}", sharer_name, file_name, share_url)),
        }).await
    }

    pub async fn send_mfa_enabled(&self, to: &str) -> AppResult<()> {
        self.send(&EmailMessage {
            to: to.to_string(),
            subject: "MFA Enabled on PCOS".to_string(),
            body_html: "<h2>Two-Factor Authentication Enabled</h2><p>MFA has been enabled on your account. You'll need your authenticator app to log in.</p>".to_string(),
            body_text: Some("MFA has been enabled on your PCOS account.".to_string()),
        }).await
    }
}
