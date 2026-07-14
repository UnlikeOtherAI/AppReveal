# Windows

AppReveal has two Windows integration tracks:

- Native .NET apps: `Windows/AppReveal.Windows`
- Tauri desktop apps: `Windows/appreveal-tauri`

The native .NET and Tauri tracks expose the same MCP JSON-RPC shape as the
existing platforms: `initialize`, `tools/list`, and `tools/call` over HTTP POST,
with tool-call results wrapped as text content.

Both Windows server foundations expose unauthenticated `GET /health` diagnostics and require the generated session token for MCP POST requests.

## Native .NET

Add the `AppReveal.Windows` project to a debug-only solution reference, then
start it from app startup:

```csharp
#if DEBUG
using AppReveal.Windows;

var session = AppReveal.Start(new AppRevealOptions
{
    AppId = "com.example.windows",
    AppName = "Example Windows App",
});

Console.WriteLine(session.SessionUrl);
#endif
```

The default provider uses Windows UI Automation to enumerate current-process
windows, native elements, view trees, screenshots, menu hierarchy, focus, and
basic interactions. Apps can still override providers for framework-specific
state, logs, network calls, WebView2 DOM control, and service discovery. The
server is loopback-only by default and requires the generated per-session token exposed through
`session.SessionUrl`, `session.SessionToken`, or the `X-AppReveal-Session`
header. Discovery advertisement stays disabled unless
`EnableLoopbackDiscoveryAdvertisement` is set.

## Tauri

`Windows/appreveal-tauri` is a Rust crate for Tauri desktop apps, including
macOS Tauri/wry apps. It exposes the same HTTP MCP contract and an optional
`tauri` feature that adds a Tauri v2 plugin, Bonjour/mDNS discovery, launch
context, device info, window metadata, WebView DOM tools, window focus, and menu
inspection.

```rust
tauri::Builder::default()
    .plugin(appreveal_tauri::init())
    .run(tauri::generate_context!())?;
```

The Tauri crate always advertises the functional foundation tools
`launch_context`, `device_info`, and `batch`. The optional `tauri` feature adds
real launch context, device info, and window metadata from a `tauri::AppHandle`;
`list_windows`, `focus_window`, and `get_menu_bar`; and live WebView DOM tools:
`get_elements`, `get_dom_interactive`, `tap_element`, `tap_text`, `tap_point`,
`type_text`, and `clear_text`.

Provider-backed tools for logs, state, navigation, feature flags, and network
capture are listed only after the app registers the corresponding real provider.
Screenshot capture, native non-WebView UI automation, recent-error capture, and
app-specific menu activation remain provider-backed extension points.
The HTTP server requires a generated session token by
default; use `ServerHandle::session_url()` or
`AppRevealTauriServer::session_url()` for manual testing, or pass an explicit
token with `ServerConfig::with_session_token`.

## Tool Parity

The native .NET package advertises functional Windows UI, state, diagnostics,
network, batch, and desktop window/menu tools. WebView DOM tools are advertised
only when a host WebView provider is registered.

The Tauri crate advertises its implemented foundation tools, runtime-backed
Tauri tools, available provider-backed built-ins, and caller-registered
extensions. Generic Tauri supports menu inspection, but not synthetic activation
of arbitrary native menu items, so hosts should register an app-specific command
when they need write-side menu control.

For production release builds, keep AppReveal behind debug guards just like the
other platforms.
