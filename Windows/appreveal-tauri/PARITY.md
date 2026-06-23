# Tauri parity notes

This crate is the Windows-focused Tauri foundation for AppReveal. It provides the shared HTTP MCP contract, generated session-token authentication, Tauri launch/window metadata, and provider hooks for state, navigation, feature flags, logs, network capture, and future UI tooling.

Implemented:

- `initialize`, `tools/list`, and `tools/call` over HTTP POST.
- Generated per-session token via `ServerHandle::session_url()` or `AppRevealTauriServer::session_url()`.
- Optional `tauri` feature for `tauri::AppHandle` integration.
- Provider-backed hooks for launch context, device info, windows, logs, state, navigation, feature flags, and network capture.
- `tools/list` advertises only always-functional built-ins, provider-backed built-ins whose providers are configured, and caller-registered tools.

Parity gaps:

- This is not the macOS `tauri/wry` runtime integration requested by GitHub issue #40.
- No Rust Bonjour/mDNS advertiser is included yet.
- Native UI, DOM/WebView, screenshots, interaction, menu actions, and recent-error capture need real provider implementations before they should be advertised.
- The crate does not currently expose a Tauri plugin manifest/API shape.

Next milestones:

- Add a cross-platform Tauri plugin wrapper around the current server handle.
- Add optional mDNS discovery with the same `_appreveal._tcp` TXT records used by Swift platforms.
- Add WebView and native UI providers for Tauri/wry windows.
- Keep the Windows crate behavior provider-backed so WPF, WinUI, WebView2, Tauri, and React Native Windows can share one tool contract.
