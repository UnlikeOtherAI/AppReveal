# appreveal-tauri

Debug-only AppReveal MCP foundation for Rust and Tauri Windows apps.

This crate starts a small loopback HTTP JSON-RPC server that implements
AppReveal's MCP contract: `initialize`, `tools/list`, and `tools/call`.
Foundation tools are always available, and provider-backed tools are advertised
only after the host app registers real providers.

## Install

```sh
cargo add appreveal-tauri --version 0.10.0
```

For Tauri integration:

```toml
[dependencies]
appreveal-tauri = { version = "0.10.0", features = ["tauri"] }
```

## Start in debug builds

```rust
#[cfg(debug_assertions)]
let mut appreveal = appreveal_tauri::AppReveal::new();

#[cfg(debug_assertions)]
{
    appreveal.start(appreveal_tauri::ServerConfig::localhost(0))?;
    if let Some(url) = appreveal.session_url() {
        println!("AppReveal listening at {url}");
    }
}
```

With the optional `tauri` feature, the crate can derive launch context, device
info, and window metadata from a `tauri::AppHandle`:

```rust
#[cfg(debug_assertions)]
appreveal_tauri::start_tauri_server_managed(
    app.handle().clone(),
    appreveal_tauri::ServerConfig::localhost(0),
)?;
```

The server requires a generated session token by default. Use
`ServerHandle::session_url()` or `AppRevealTauriServer::session_url()` for the
tokenized URL during manual testing.

## Scope

The crate currently provides the Windows-focused Tauri foundation, shared HTTP
MCP protocol handling, session-token authentication, provider hooks, and
optional Tauri app metadata integration. Native UI, DOM/WebView, screenshots,
interaction, menu actions, and recent-error capture are advertised only when a
host app registers real implementations.
