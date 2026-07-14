# Tauri parity notes

This crate is AppReveal's Rust/Tauri desktop bridge. It provides the shared HTTP
MCP contract, generated session-token authentication, a Tauri v2 plugin
entrypoint, Bonjour/mDNS discovery, Tauri launch/window metadata, live WebView
DOM inspection, DOM interaction helpers, menu inspection, and provider hooks for
state, navigation, feature flags, logs, network capture, and host-specific UI
tooling.

Implemented:

- `initialize`, `tools/list`, and `tools/call` over HTTP POST.
- Generated per-session token via `ServerHandle::session_url()` or
  `AppRevealTauriServer::session_url()`.
- Optional Rust mDNS advertiser for `_appreveal._tcp.local.` with the same
  `transport=streamable-http` and `auth=session-token` TXT records used by the
  Swift platforms.
- `appreveal_tauri::init()` and `init_with_config(...)` Tauri plugin entrypoints
  that start the MCP server only in debug builds by default.
- Optional `tauri` feature for `tauri::AppHandle` integration.
- Tauri window metadata and `focus_window`.
- Live Tauri WebView DOM tools: `get_elements`, `get_dom_interactive`,
  `tap_element`, `tap_text`, `tap_point`, `type_text`, and `clear_text`.
- Tauri application menu inspection through `get_menu_bar`.
- Provider-backed hooks for launch context, device info, windows, logs, state,
  navigation, feature flags, and network capture.
- `tools/list` advertises only always-functional built-ins, Tauri runtime tools,
  provider-backed built-ins whose providers are configured, and caller-registered
  tools.

Known limits:

- Generic Tauri exposes menu inspection, but not a safe cross-platform API to
  synthesize activation of arbitrary native menu items. Host apps can still
  register a custom command/tool for app-specific menu actions.
- Screenshot capture and native non-WebView UI automation remain provider-backed
  extension points.
- DOM tools operate on Tauri WebViews through JavaScript evaluation and require
  the target page to allow normal in-page DOM event dispatch.
