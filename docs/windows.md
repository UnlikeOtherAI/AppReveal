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

`Windows/appreveal-tauri` is a Rust crate for Tauri apps. It exposes the same
HTTP MCP contract and an optional `tauri` feature that derives launch context,
device info, and window metadata from a `tauri::AppHandle`.

```rust
#[cfg(debug_assertions)]
appreveal_tauri::start_tauri_server_managed(
    app.handle().clone(),
    appreveal_tauri::ServerConfig::localhost(0),
)?;

#[cfg(debug_assertions)]
if let Some(url) = app
    .state::<appreveal_tauri::AppRevealTauriServer>()
    .session_url()?
{
    println!("AppReveal listening at {url}");
}
```

The Tauri crate always advertises the functional foundation tools
`launch_context`, `device_info`, and `batch`. The optional `tauri` feature adds
real launch context, device info, and window metadata from a `tauri::AppHandle`,
so `list_windows` is advertised when that window provider is configured.

Provider-backed tools for logs, state, navigation, feature flags, and network
capture are listed only after the app registers the corresponding real provider.
Native UI, DOM/WebView, screenshots, interaction, menu actions, and recent-error
capture are not advertised until the app registers real tools/providers for
those features.
The HTTP server requires a generated session token by
default; use `ServerHandle::session_url()` or
`AppRevealTauriServer::session_url()` for manual testing, or pass an explicit
token with `ServerConfig::with_session_token`.

## Tool Parity

The native .NET package advertises functional Windows UI, state, diagnostics,
network, batch, and desktop window/menu tools. WebView DOM tools are advertised
only when a host WebView provider is registered.

The Tauri crate advertises its implemented foundation tools, available
provider-backed built-ins, and caller-registered extensions. It does not list
state, diagnostics, native UI, menu, interaction, screenshot, DOM, or
recent-error tools until the app supplies real implementations.

The Tauri crate is a Windows/Tauri foundation. macOS Tauri/wry DOM and native UI providers remain a separate parity milestone tracked in `Windows/appreveal-tauri/PARITY.md`.

For production release builds, keep AppReveal behind debug guards just like the
other platforms.
