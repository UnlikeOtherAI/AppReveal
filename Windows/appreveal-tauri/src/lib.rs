//! AppReveal foundation for Rust/Tauri desktop applications.
//!
//! This crate exposes AppReveal's Streamable HTTP-ish JSON-RPC contract over a
//! tiny `std::net::TcpListener` server. It is intentionally small and reusable:
//! register provider hooks, start the server, and AppReveal-compatible clients
//! can call `initialize`, `tools/list`, and `tools/call`.

mod builtins;
mod error;
mod protocol;
mod providers;
mod registry;
mod server;

#[cfg(feature = "tauri")]
pub mod tauri_integration;

pub use builtins::{register_builtin_tools, registry_with_builtins};
pub use error::{AppRevealError, Result};
pub use protocol::{handle_request, JsonRpcRequest, JsonRpcResponse, RpcError};
pub use providers::{LogQuery, NetworkQuery, ProviderRegistry, WindowInfo};
pub use registry::{Tool, ToolMetadata, ToolRegistry, ToolResult};
pub use server::{start_server, BonjourConfig, ServerConfig, ServerHandle};

#[cfg(feature = "tauri")]
pub use tauri_integration::{
    configure_tauri_providers, init, init_with_config, providers_from_tauri, start_tauri_server,
    start_tauri_server_managed, AppRevealTauriServer, TauriPluginConfig,
};

pub const APPREVEAL_PROTOCOL_VERSION: &str = "2025-06-18";
pub const APPREVEAL_SERVER_NAME: &str = "AppReveal";
pub const APPREVEAL_VERSION: &str = env!("CARGO_PKG_VERSION");

/// High-level facade for the common AppReveal lifecycle.
pub struct AppReveal {
    providers: ProviderRegistry,
    registry: ToolRegistry,
    handle: Option<ServerHandle>,
}

impl AppReveal {
    /// Build an AppReveal instance with empty default providers and built-in tools.
    pub fn new() -> Self {
        Self::with_providers(ProviderRegistry::new())
    }

    /// Build an AppReveal instance around a caller-supplied provider registry.
    pub fn with_providers(providers: ProviderRegistry) -> Self {
        let registry = registry_with_builtins(providers.clone());
        Self {
            providers,
            registry,
            handle: None,
        }
    }

    pub fn providers(&self) -> &ProviderRegistry {
        &self.providers
    }

    pub fn registry(&self) -> &ToolRegistry {
        &self.registry
    }

    pub fn register_tool(&self, tool: Tool) -> Result<()> {
        self.registry.register(tool)
    }

    pub fn register_launch_context_provider<F>(&self, provider: F)
    where
        F: Fn() -> serde_json::Value + Send + Sync + 'static,
    {
        self.providers.set_launch_context_provider(provider);
    }

    pub fn register_device_info_provider<F>(&self, provider: F)
    where
        F: Fn() -> serde_json::Value + Send + Sync + 'static,
    {
        self.providers.set_device_info_provider(provider);
    }

    pub fn register_window_provider<F>(&self, provider: F)
    where
        F: Fn() -> Vec<WindowInfo> + Send + Sync + 'static,
    {
        self.providers.set_window_provider(provider);
    }

    pub fn register_log_provider<F>(&self, provider: F)
    where
        F: Fn(LogQuery) -> serde_json::Value + Send + Sync + 'static,
    {
        self.providers.set_log_provider(provider);
    }

    pub fn register_state_provider<F>(&self, provider: F)
    where
        F: Fn() -> serde_json::Value + Send + Sync + 'static,
    {
        self.providers.set_state_provider(provider);
    }

    pub fn register_navigation_provider<F>(&self, provider: F)
    where
        F: Fn() -> serde_json::Value + Send + Sync + 'static,
    {
        self.providers.set_navigation_provider(provider);
    }

    pub fn register_feature_flag_provider<F>(&self, provider: F)
    where
        F: Fn() -> serde_json::Value + Send + Sync + 'static,
    {
        self.providers.set_feature_flag_provider(provider);
    }

    pub fn register_network_provider<F>(&self, provider: F)
    where
        F: Fn(NetworkQuery) -> serde_json::Value + Send + Sync + 'static,
    {
        self.providers.set_network_provider(provider);
    }

    /// Start the HTTP JSON-RPC server. Returns the actual socket address.
    pub fn start(&mut self, config: ServerConfig) -> Result<std::net::SocketAddr> {
        if self.handle.is_some() {
            return Err(AppRevealError::AlreadyStarted);
        }

        let handle = start_server(config, self.registry.clone())?;
        let addr = handle.local_addr();
        self.handle = Some(handle);
        Ok(addr)
    }

    /// Stop the server if it is running.
    pub fn stop(&mut self) -> Result<()> {
        if let Some(mut handle) = self.handle.take() {
            handle.stop()?;
        }
        Ok(())
    }

    pub fn local_addr(&self) -> Option<std::net::SocketAddr> {
        self.handle.as_ref().map(ServerHandle::local_addr)
    }

    pub fn session_token(&self) -> Option<&str> {
        self.handle.as_ref().and_then(ServerHandle::session_token)
    }

    pub fn session_url(&self) -> Option<String> {
        self.handle.as_ref().map(ServerHandle::session_url)
    }

    pub fn is_running(&self) -> bool {
        self.handle.is_some()
    }
}

impl Default for AppReveal {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for AppReveal {
    fn drop(&mut self) {
        let _ = self.stop();
    }
}
