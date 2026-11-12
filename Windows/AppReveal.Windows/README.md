# AppReveal.Windows

Debug-only in-app MCP server foundation for native Windows .NET apps.

AppReveal.Windows starts a loopback HTTP JSON-RPC server that exposes the
AppReveal MCP contract for agent-driven inspection and interaction. The default
provider uses Windows UI Automation for current-process windows, elements,
screenshots, menu hierarchy, focus, and basic interactions. Hosts can register
providers for app state, navigation, feature flags, logs, network calls, and
WebView tooling.

## Install

```sh
dotnet add package AppReveal.Windows --version 0.10.1
```

## Start in debug builds

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

The server is intended for debug builds. It binds to loopback by default and
requires the generated per-session token exposed through `SessionUrl`,
`SessionToken`, or the `X-AppReveal-Session` header.

## Providers

```csharp
AppReveal.Start(new AppRevealOptions
{
    StateProvider = new MyStateProvider(),
    NavigationProvider = new MyNavigationProvider(),
    LogProvider = new MyLogProvider(),
    NetworkProvider = new MyNetworkProvider(),
});
```

Provider-backed tools are advertised only when the host supplies real
implementations. Keep AppReveal guarded out of production release builds.

## Interaction contracts

Native text editing requires a writable UI Automation ValuePattern and replaces
its value. With no `element_id`, it uses the focused field inside the selected
app window. Disabled/read-only targets fail; there is no global keyboard
fallback. `scroll` requires a ScrollPattern and returns `not_scrolled` at a
boundary. `scroll_to_element` verifies visibility. Element IDs come from UIA
runtime IDs so inventory, tree, menu and interaction calls identify the same
control, including repeated AutomationIds.

`tap_point` uses physical screen coordinates and rejects points outside the
selected app window. `navigate_back` and `dismiss_modal` require that window to
already be foreground; their `input_sent` result confirms delivery of the
shortcut, not that the host navigated or closed a modal. Use app state or a fresh
inventory to verify the effect. `open_deeplink` delegates to the Windows URI
handler; it does not verify navigation in the current app.

WebView methods require a host implementation of `IAppRevealWebViewProvider`;
the default native provider does not implement DOM tools. A registered WebView
provider must implement all advertised WebView methods and return
`{ "success": false, "error": "..." }` for unsupported/failed actions.
Provider failures set MCP `isError`, including inside `batch`.
`stop_on_error` stops on returned failures as well as exceptions; nested batches
and batches over 100 actions are rejected. HTTP bodies are limited to 1 MiB.
