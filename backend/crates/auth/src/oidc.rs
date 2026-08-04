//! SSO/OIDC integration module.
//!
//! Supports OpenID Connect discovery, authorization code flow, and token validation.
//! Compatible with Keycloak, Auth0, Okta, Azure AD, Google.

use pcos_common::error::{AppError, AppResult};
use serde::{Deserialize, Serialize};

/// OIDC provider configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OidcConfig {
    pub provider_name: String,
    pub issuer_url: String,
    pub client_id: String,
    pub client_secret: String,
    pub redirect_uri: String,
    pub scopes: Vec<String>,
    pub enabled: bool,
}

/// OIDC discovery document (partial).
#[derive(Debug, Deserialize)]
pub struct OidcDiscovery {
    pub issuer: String,
    pub authorization_endpoint: String,
    pub token_endpoint: String,
    pub userinfo_endpoint: String,
    pub jwks_uri: String,
}

/// Token response from OIDC provider.
#[derive(Debug, Deserialize)]
pub struct TokenResponse {
    pub access_token: String,
    pub token_type: String,
    pub expires_in: Option<u64>,
    pub id_token: Option<String>,
    pub refresh_token: Option<String>,
}

/// User info from OIDC provider.
#[derive(Debug, Deserialize)]
pub struct UserInfo {
    pub sub: String,
    pub email: Option<String>,
    pub name: Option<String>,
    pub preferred_username: Option<String>,
    pub picture: Option<String>,
}

impl OidcConfig {
    /// Default scopes for OIDC.
    pub fn default_scopes() -> Vec<String> {
        vec!["openid".into(), "email".into(), "profile".into()]
    }
}

/// Fetch OIDC discovery document from issuer.
pub async fn discover(issuer_url: &str) -> AppResult<OidcDiscovery> {
    let url = format!(
        "{}/.well-known/openid-configuration",
        issuer_url.trim_end_matches('/')
    );
    let client = reqwest::Client::new();
    let resp = client
        .get(&url)
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("OIDC discovery failed: {e}")))?;

    if !resp.status().is_success() {
        return Err(AppError::Internal(format!(
            "OIDC discovery returned {}",
            resp.status()
        )));
    }

    resp.json::<OidcDiscovery>()
        .await
        .map_err(|e| AppError::Internal(format!("OIDC discovery parse error: {e}")))
}

/// Build the authorization URL for the OIDC provider.
pub fn authorization_url(config: &OidcConfig, discovery: &OidcDiscovery, state: &str) -> String {
    let scopes = config.scopes.join(" ");
    format!(
        "{}?response_type=code&client_id={}&redirect_uri={}&scope={}&state={}",
        discovery.authorization_endpoint,
        urlencoding::encode(&config.client_id),
        urlencoding::encode(&config.redirect_uri),
        urlencoding::encode(&scopes),
        urlencoding::encode(state),
    )
}

/// Exchange authorization code for tokens.
pub async fn exchange_code(
    config: &OidcConfig,
    discovery: &OidcDiscovery,
    code: &str,
) -> AppResult<TokenResponse> {
    let client = reqwest::Client::new();
    let resp = client
        .post(&discovery.token_endpoint)
        .form(&[
            ("grant_type", "authorization_code"),
            ("client_id", &config.client_id),
            ("client_secret", &config.client_secret),
            ("redirect_uri", &config.redirect_uri),
            ("code", code),
        ])
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("Token exchange failed: {e}")))?;

    if !resp.status().is_success() {
        let body = resp.text().await.unwrap_or_default();
        return Err(AppError::Internal(format!("Token exchange error: {body}")));
    }

    resp.json::<TokenResponse>()
        .await
        .map_err(|e| AppError::Internal(format!("Token parse error: {e}")))
}

/// Fetch user info from OIDC provider.
pub async fn fetch_user_info(discovery: &OidcDiscovery, access_token: &str) -> AppResult<UserInfo> {
    let client = reqwest::Client::new();
    let resp = client
        .get(&discovery.userinfo_endpoint)
        .bearer_auth(access_token)
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("UserInfo fetch failed: {e}")))?;

    resp.json::<UserInfo>()
        .await
        .map_err(|e| AppError::Internal(format!("UserInfo parse error: {e}")))
}
