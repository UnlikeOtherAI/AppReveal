# appreveal-tauri

Debug-only AppReveal MCP support for Rust and Tauri desktop apps, including
macOS Tauri/wry WebViews.

This crate starts a small loopback HTTP JSON-RPC server that implements
AppReveal's MCP contract: `initialize`, `tools/list`, and `tools/call`.
Foundation tools are always available. With the `tauri` feature, the crate also
adds a Tauri v2 plugin entrypoint, Bonjour/mDNS discovery, live WebView DOM
inspection, DOM tap/type helpers, window focus, menu inspection, and Tauri app
metadata.

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

For Tauri v2 apps, install the plugin in your builder. It starts only in debug
builds by default, binds a token-protected MCP server, advertises
`_appreveal._tcp` via Bonjour/mDNS, and prints the tokenized session URL:

```rust
tauri::Builder::default()
    .plugin(appreveal_tauri::init())
    .run(tauri::generate_context!())?;
```

Use `init_with_config(appreveal_tauri::TauriPluginConfig { ... })` when an app
needs a custom port, host, discovery name, or release-build override.

For non-plugin Rust hosts, the lower-level server facade is still available:

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

The optional `tauri` feature also exposes the managed starter if your app cannot
use Tauri's plugin builder:

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

For a direct MCP smoke test without a Tauri app, run:

```sh
cargo run --example serve
```

Then curl the printed URL with `initialize`, `tools/list`, or `tools/call`.

## Tauri tools

The Tauri plugin registers these runtime-backed tools:

- `get_elements` and `get_dom_interactive` inspect live interactive DOM nodes in
  Tauri WebViews using `eval_with_callback`.
- `tap_element`, `tap_text`, `tap_point`, `type_text`, and `clear_text` dispatch
  DOM events back into the WebView.
- `list_windows` comes from the Tauri window provider, and `focus_window` focuses
  a Tauri WebView window by label.
- `get_menu_bar` reads the Tauri menu tree when the runtime exposes one.

## Scope

The crate now provides a cross-platform Tauri desktop MCP bridge. Generic Tauri
does not expose a safe API for programmatically activating native menu items, so
menu support is inspect-only unless a host app registers its own custom command.
Screenshot capture and native non-WebView UI automation remain provider-backed
extension points.
