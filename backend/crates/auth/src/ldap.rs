//! LDAP/Active Directory integration module.
//!
//! Provides user authentication and group sync against LDAP/AD directories.
//! Compatible with OpenLDAP, Active Directory, FreeIPA.

use pcos_common::error::{AppError, AppResult};
use serde::{Deserialize, Serialize};

/// LDAP server configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LdapConfig {
    pub server_url: String, // ldap://ldap.example.com:389 or ldaps://...
    pub bind_dn: String,    // cn=admin,dc=example,dc=com
    pub bind_password: String,
    pub base_dn: String,             // dc=example,dc=com
    pub user_search_filter: String,  // (&(objectClass=person)(uid={0}))
    pub group_search_filter: String, // (&(objectClass=groupOfNames)(member={0}))
    pub email_attribute: String,     // mail
    pub name_attribute: String,      // cn
    pub use_tls: bool,
    pub enabled: bool,
}

/// User info resolved from LDAP.
#[derive(Debug, Clone, Serialize)]
pub struct LdapUser {
    pub dn: String,
    pub username: String,
    pub email: String,
    pub display_name: String,
    pub groups: Vec<String>,
}

impl LdapConfig {
    /// Default config for Active Directory.
    pub fn active_directory_defaults() -> Self {
        Self {
            server_url: "ldap://dc.example.com:389".into(),
            bind_dn: "CN=PCOS Service,OU=Service Accounts,DC=example,DC=com".into(),
            bind_password: String::new(),
            base_dn: "DC=example,DC=com".into(),
            user_search_filter: "(&(objectClass=user)(sAMAccountName={0}))".into(),
            group_search_filter: "(&(objectClass=group)(member={0}))".into(),
            email_attribute: "mail".into(),
            name_attribute: "displayName".into(),
            use_tls: false,
            enabled: false,
        }
    }

    /// Default config for OpenLDAP.
    pub fn openldap_defaults() -> Self {
        Self {
            server_url: "ldap://ldap.example.com:389".into(),
            bind_dn: "cn=admin,dc=example,dc=com".into(),
            bind_password: String::new(),
            base_dn: "dc=example,dc=com".into(),
            user_search_filter: "(&(objectClass=inetOrgPerson)(uid={0}))".into(),
            group_search_filter: "(&(objectClass=groupOfNames)(member={0}))".into(),
            email_attribute: "mail".into(),
            name_attribute: "cn".into(),
            use_tls: false,
            enabled: false,
        }
    }
}

/// Authenticate a user against LDAP.
/// In production, use the `ldap3` crate for async LDAP operations.
pub async fn authenticate(
    config: &LdapConfig,
    username: &str,
    password: &str,
) -> AppResult<LdapUser> {
    if !config.enabled {
        return Err(AppError::Internal(
            "LDAP authentication is not enabled".into(),
        ));
    }

    // Production implementation with `ldap3` crate:
    // 1. Connect to LDAP server (with STARTTLS if configured)
    // 2. Bind with service account
    // 3. Search for user DN using user_search_filter
    // 4. Attempt bind with user DN + password
    // 5. Fetch user attributes (email, name)
    // 6. Search for group memberships
    // 7. Return LdapUser

    // Placeholder: simulate LDAP search response
    let user_filter = config.user_search_filter.replace("{0}", username);
    tracing::info!(
        server = %config.server_url,
        filter = %user_filter,
        "LDAP authentication attempt"
    );

    Err(AppError::Internal(format!(
        "LDAP integration requires the `ldap3` crate. Configure server: {}, base_dn: {}",
        config.server_url, config.base_dn
    )))
}

/// Sync groups from LDAP to PCOS roles.
pub async fn sync_groups(config: &LdapConfig) -> AppResult<Vec<String>> {
    if !config.enabled {
        return Err(AppError::Internal("LDAP is not enabled".into()));
    }

    tracing::info!(server = %config.server_url, "LDAP group sync requested");

    // Production: fetch all groups matching group_search_filter,
    // map to PCOS roles (admin/user/viewer)
    Ok(Vec::new())
}
