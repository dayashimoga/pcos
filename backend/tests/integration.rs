#[cfg(test)]
mod tests {
    use reqwest::Client;
    use serde_json::{json, Value};

    /// Integration test base URL — set via TEST_API_URL env var or default to localhost:8080
    fn api_url() -> String {
        std::env::var("TEST_API_URL").unwrap_or_else(|_| "http://localhost:8080".to_string())
    }

    fn client() -> Client {
        Client::builder()
            .timeout(std::time::Duration::from_secs(10))
            .build()
            .unwrap()
    }

    /// Generate a unique test email to avoid conflicts between test runs.
    fn test_email() -> String {
        format!("test_{}@pcos-test.local", uuid::Uuid::new_v4().to_string()[..8].to_string())
    }

    // ─── Auth Integration Tests ──────────────────────────────

    #[tokio::test]
    #[ignore] // Run with: cargo test --test integration -- --ignored
    async fn test_health_check() {
        let resp = client().get(format!("{}/health", api_url())).send().await.unwrap();
        assert_eq!(resp.status(), 200);
        let body: Value = resp.json().await.unwrap();
        assert_eq!(body["status"], "healthy");
        assert!(body["version"].is_string());
        assert!(body["uptime_secs"].is_number());
    }

    #[tokio::test]
    #[ignore]
    async fn test_full_auth_flow() {
        let c = client();
        let base = api_url();
        let email = test_email();
        let password = "TestPass123";

        // 1. Register
        let resp = c.post(format!("{base}/api/v1/auth/register"))
            .json(&json!({ "email": email, "password": password, "display_name": "Test User" }))
            .send().await.unwrap();
        assert_eq!(resp.status(), 201, "Register failed: {:?}", resp.text().await);

        // Re-fetch (register consumed the response)
        let resp = c.post(format!("{base}/api/v1/auth/login"))
            .json(&json!({ "email": email, "password": password }))
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);
        let login_body: Value = resp.json().await.unwrap();
        let access_token = login_body["tokens"]["access_token"].as_str().unwrap();
        let refresh_token = login_body["tokens"]["refresh_token"].as_str().unwrap();
        assert!(!access_token.is_empty());
        assert!(!refresh_token.is_empty());

        // 2. Get profile
        let resp = c.get(format!("{base}/api/v1/users/me"))
            .bearer_auth(access_token)
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);
        let profile: Value = resp.json().await.unwrap();
        assert_eq!(profile["email"], email);

        // 3. Refresh token
        let resp = c.post(format!("{base}/api/v1/auth/refresh"))
            .json(&json!({ "refresh_token": refresh_token }))
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);
        let refresh_body: Value = resp.json().await.unwrap();
        let new_access = refresh_body["tokens"]["access_token"].as_str().unwrap();
        assert!(!new_access.is_empty());

        // 4. Logout
        let resp = c.post(format!("{base}/api/v1/auth/logout"))
            .json(&json!({ "refresh_token": refresh_body["tokens"]["refresh_token"] }))
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);

        // 5. Old token should fail after logout (refresh revoked)
        let resp = c.post(format!("{base}/api/v1/auth/refresh"))
            .json(&json!({ "refresh_token": refresh_token }))
            .send().await.unwrap();
        assert!(resp.status().is_client_error());
    }

    #[tokio::test]
    #[ignore]
    async fn test_register_validation() {
        let c = client();
        let base = api_url();

        // Weak password
        let resp = c.post(format!("{base}/api/v1/auth/register"))
            .json(&json!({ "email": "valid@test.com", "password": "short", "display_name": "Test" }))
            .send().await.unwrap();
        assert!(resp.status().is_client_error());

        // Invalid email
        let resp = c.post(format!("{base}/api/v1/auth/register"))
            .json(&json!({ "email": "not-an-email", "password": "ValidPass1", "display_name": "Test" }))
            .send().await.unwrap();
        assert!(resp.status().is_client_error());

        // Empty display name
        let resp = c.post(format!("{base}/api/v1/auth/register"))
            .json(&json!({ "email": "valid2@test.com", "password": "ValidPass1", "display_name": "" }))
            .send().await.unwrap();
        assert!(resp.status().is_client_error());
    }

    #[tokio::test]
    #[ignore]
    async fn test_unauthorized_access() {
        let c = client();
        let base = api_url();

        // No token
        let resp = c.get(format!("{base}/api/v1/users/me")).send().await.unwrap();
        assert_eq!(resp.status(), 401);

        // Bad token
        let resp = c.get(format!("{base}/api/v1/users/me"))
            .bearer_auth("invalid-token-here")
            .send().await.unwrap();
        assert_eq!(resp.status(), 401);
    }

    // ─── File Integration Tests ──────────────────────────────

    /// Helper: register + login and return access token
    async fn get_auth_token(c: &Client) -> String {
        let base = api_url();
        let email = test_email();
        c.post(format!("{base}/api/v1/auth/register"))
            .json(&json!({ "email": email, "password": "TestPass123", "display_name": "File Test" }))
            .send().await.unwrap();
        let resp = c.post(format!("{base}/api/v1/auth/login"))
            .json(&json!({ "email": email, "password": "TestPass123" }))
            .send().await.unwrap();
        let body: Value = resp.json().await.unwrap();
        body["tokens"]["access_token"].as_str().unwrap().to_string()
    }

    #[tokio::test]
    #[ignore]
    async fn test_folder_crud() {
        let c = client();
        let base = api_url();
        let token = get_auth_token(&c).await;

        // Create folder
        let resp = c.post(format!("{base}/api/v1/folders"))
            .bearer_auth(&token)
            .json(&json!({ "name": "Test Folder" }))
            .send().await.unwrap();
        assert_eq!(resp.status(), 201);
        let folder: Value = resp.json().await.unwrap();
        let folder_id = folder["id"].as_str().unwrap();

        // List root — should contain our folder
        let resp = c.get(format!("{base}/api/v1/folders"))
            .bearer_auth(&token)
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);
        let list: Value = resp.json().await.unwrap();
        assert!(list["entries"].as_array().unwrap().iter().any(|e| e["id"] == folder_id));

        // Rename folder
        let resp = c.put(format!("{base}/api/v1/folders/{folder_id}"))
            .bearer_auth(&token)
            .json(&json!({ "name": "Renamed Folder" }))
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);

        // Delete (trash)
        let resp = c.delete(format!("{base}/api/v1/files/{folder_id}"))
            .bearer_auth(&token)
            .send().await.unwrap();
        assert_eq!(resp.status(), 204);

        // Verify in trash
        let resp = c.get(format!("{base}/api/v1/trash"))
            .bearer_auth(&token)
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);

        // Restore
        let resp = c.post(format!("{base}/api/v1/trash/{folder_id}/restore"))
            .bearer_auth(&token)
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);
    }

    #[tokio::test]
    #[ignore]
    async fn test_file_upload_download() {
        let c = client();
        let base = api_url();
        let token = get_auth_token(&c).await;

        // Upload file
        let form = reqwest::multipart::Form::new()
            .text("parent_id", "")
            .part("file", reqwest::multipart::Part::bytes(b"Hello PCOS!".to_vec())
                .file_name("test.txt")
                .mime_str("text/plain").unwrap());

        let resp = c.post(format!("{base}/api/v1/files/upload"))
            .bearer_auth(&token)
            .multipart(form)
            .send().await.unwrap();
        assert_eq!(resp.status(), 201);
        let upload: Value = resp.json().await.unwrap();
        let file_id = upload["file"]["id"].as_str().unwrap();

        // Download file
        let resp = c.get(format!("{base}/api/v1/files/{file_id}/download"))
            .bearer_auth(&token)
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);
        let body = resp.bytes().await.unwrap();
        assert_eq!(&body[..], b"Hello PCOS!");

        // Preview file (inline)
        let resp = c.get(format!("{base}/api/v1/files/{file_id}/preview"))
            .bearer_auth(&token)
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);
        assert!(resp.headers()["content-disposition"].to_str().unwrap().contains("inline"));

        // Delete
        let resp = c.delete(format!("{base}/api/v1/files/{file_id}"))
            .bearer_auth(&token)
            .send().await.unwrap();
        assert_eq!(resp.status(), 204);
    }

    // ─── Device & Analytics Tests ────────────────────────────

    #[tokio::test]
    #[ignore]
    async fn test_device_and_analytics() {
        let c = client();
        let base = api_url();
        let token = get_auth_token(&c).await;

        // Register device
        let resp = c.post(format!("{base}/api/v1/devices"))
            .bearer_auth(&token)
            .json(&json!({ "name": "Test Laptop", "device_type": "desktop", "os": "Windows", "os_version": "11" }))
            .send().await.unwrap();
        assert_eq!(resp.status(), 201);
        let device: Value = resp.json().await.unwrap();
        let device_id = device["id"].as_str().unwrap();

        // List devices
        let resp = c.get(format!("{base}/api/v1/devices"))
            .bearer_auth(&token)
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);

        // Heartbeat
        let resp = c.put(format!("{base}/api/v1/devices/{device_id}/heartbeat"))
            .bearer_auth(&token)
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);

        // Analytics overview
        let resp = c.get(format!("{base}/api/v1/analytics/overview"))
            .bearer_auth(&token)
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);
        let analytics: Value = resp.json().await.unwrap();
        assert!(analytics["total_devices"].as_i64().unwrap() >= 1);

        // Cleanup
        let resp = c.delete(format!("{base}/api/v1/devices/{device_id}"))
            .bearer_auth(&token)
            .send().await.unwrap();
        assert_eq!(resp.status(), 204);
    }

    // ─── Notification Tests ──────────────────────────────────

    #[tokio::test]
    #[ignore]
    async fn test_notification_flow() {
        let c = client();
        let base = api_url();
        let token = get_auth_token(&c).await;

        // Create notification
        let resp = c.post(format!("{base}/api/v1/notifications"))
            .bearer_auth(&token)
            .json(&json!({ "title": "Test Alert", "body": "Something happened" }))
            .send().await.unwrap();
        assert_eq!(resp.status(), 201);
        let notif: Value = resp.json().await.unwrap();
        let notif_id = notif["id"].as_str().unwrap();

        // Unread count
        let resp = c.get(format!("{base}/api/v1/notifications/unread-count"))
            .bearer_auth(&token)
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);
        let count: Value = resp.json().await.unwrap();
        assert!(count["unread_count"].as_i64().unwrap() >= 1);

        // Mark read
        let resp = c.put(format!("{base}/api/v1/notifications/{notif_id}/read"))
            .bearer_auth(&token)
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);

        // List
        let resp = c.get(format!("{base}/api/v1/notifications"))
            .bearer_auth(&token)
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);
    }

    // ─── Search Tests ────────────────────────────────────────

    #[tokio::test]
    #[ignore]
    async fn test_search() {
        let c = client();
        let base = api_url();
        let token = get_auth_token(&c).await;

        // Search (empty results expected for fresh user)
        let resp = c.get(format!("{base}/api/v1/search"))
            .bearer_auth(&token)
            .query(&[("q", "nonexistent-file")])
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);
    }

    // ─── Storage Stats Tests ─────────────────────────────────

    #[tokio::test]
    #[ignore]
    async fn test_storage_stats() {
        let c = client();
        let base = api_url();
        let token = get_auth_token(&c).await;

        let resp = c.get(format!("{base}/api/v1/storage/stats"))
            .bearer_auth(&token)
            .send().await.unwrap();
        assert_eq!(resp.status(), 200);
        let stats: Value = resp.json().await.unwrap();
        assert!(stats["total_files"].is_number());
        assert!(stats["total_folders"].is_number());
        assert!(stats["total_size_bytes"].is_number());
    }
}
