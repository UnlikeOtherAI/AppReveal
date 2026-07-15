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
