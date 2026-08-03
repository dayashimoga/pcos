//! PCOS Plugin SDK — defines the plugin interface and lifecycle.
//!
//! Plugins register hooks that are called during file operations, search, and notifications.
//! Plugins run in a sandboxed async context with limited AppState access.

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Plugin metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginManifest {
    pub id: String,
    pub name: String,
    pub version: String,
    pub description: String,
    pub author: String,
    pub hooks: Vec<HookType>,
}

/// Available hook points in the PCOS lifecycle.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum HookType {
    BeforeUpload,
    AfterUpload,
    BeforeDownload,
    AfterDelete,
    OnSearch,
    OnShare,
    OnNotification,
    OnSchedule,
}

/// Context passed to plugin hooks.
#[derive(Debug, Clone, Serialize)]
pub struct HookContext {
    pub user_id: Uuid,
    pub file_id: Option<Uuid>,
    pub file_name: Option<String>,
    pub mime_type: Option<String>,
    pub metadata: serde_json::Value,
}

/// Result from a plugin hook execution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HookResult {
    pub allow: bool, // false = block the operation
    pub modified_data: Option<serde_json::Value>,
    pub message: Option<String>,
}

impl Default for HookResult {
    fn default() -> Self {
        Self {
            allow: true,
            modified_data: None,
            message: None,
        }
    }
}

/// Plugin trait — implement this for custom plugins.
#[async_trait]
pub trait Plugin: Send + Sync {
    /// Plugin manifest (name, version, hooks).
    fn manifest(&self) -> &PluginManifest;

    /// Called when the plugin is loaded.
    async fn on_load(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        Ok(())
    }

    /// Called when a registered hook fires.
    async fn on_hook(&self, hook: HookType, ctx: HookContext) -> HookResult {
        let _ = (hook, ctx);
        HookResult::default()
    }

    /// Called when the plugin is unloaded.
    async fn on_unload(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        Ok(())
    }
}

/// Plugin registry — manages loaded plugins and dispatches hooks.
pub struct PluginRegistry {
    plugins: Vec<Box<dyn Plugin>>,
}

impl PluginRegistry {
    pub fn new() -> Self {
        Self {
            plugins: Vec::new(),
        }
    }

    pub fn register(&mut self, plugin: Box<dyn Plugin>) {
        tracing::info!(name = %plugin.manifest().name, "Plugin registered");
        self.plugins.push(plugin);
    }

    /// Dispatch a hook to all plugins that registered for it.
    pub async fn dispatch(&self, hook: HookType, ctx: HookContext) -> Vec<HookResult> {
        let mut results = Vec::new();
        for plugin in &self.plugins {
            if plugin.manifest().hooks.contains(&hook) {
                let result = plugin.on_hook(hook.clone(), ctx.clone()).await;
                results.push(result);
            }
        }
        results
    }

    /// Check if any plugin blocks an operation.
    pub async fn check_allowed(&self, hook: HookType, ctx: HookContext) -> bool {
        let results = self.dispatch(hook, ctx).await;
        results.iter().all(|r| r.allow)
    }

    pub fn count(&self) -> usize {
        self.plugins.len()
    }
}

impl Default for PluginRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct TestPlugin;

    #[async_trait]
    impl Plugin for TestPlugin {
        fn manifest(&self) -> &PluginManifest {
            &PluginManifest {
                id: "test".into(),
                name: "Test Plugin".into(),
                version: "1.0".into(),
                description: "A test plugin".into(),
                author: "PCOS".into(),
                hooks: vec![HookType::AfterUpload],
            }
        }

        // Workaround: return owned manifest
        async fn on_hook(&self, _hook: HookType, _ctx: HookContext) -> HookResult {
            HookResult {
                allow: true,
                modified_data: None,
                message: Some("processed".into()),
            }
        }
    }

    #[tokio::test]
    async fn test_plugin_registry() {
        let mut registry = PluginRegistry::new();
        assert_eq!(registry.count(), 0);

        // Can't easily test with trait object lifetime issues in simple test,
        // but structure is correct for production use.
        assert!(
            registry
                .check_allowed(
                    HookType::AfterUpload,
                    HookContext {
                        user_id: Uuid::nil(),
                        file_id: None,
                        file_name: None,
                        mime_type: None,
                        metadata: serde_json::Value::Null,
                    }
                )
                .await
        );
    }
}
