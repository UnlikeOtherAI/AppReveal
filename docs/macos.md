# AppReveal -- macOS

## Requirements

- macOS 13.0+
- Swift 5.9+
- Xcode 15+

## Installation

### Swift Package Manager

Use the same package as iOS. AppReveal ships as a single Swift package with iOS and macOS platform support.

```swift
.package(url: "https://github.com/UnlikeOtherAI/AppReveal.git", from: "0.10.0")
```

## Quick start

### 1. Start the server from `AppDelegate`

Wrap the integration in `#if DEBUG` so there is no release-build footprint.

```swift
import AppKit

#if DEBUG
import AppReveal
#endif

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        AppReveal.start()

        // Optional: register providers for deeper inspection
        AppReveal.registerStateProvider(myStateContainer)
        AppReveal.registerNavigationProvider(myRouter)
        AppReveal.registerFeatureFlagProvider(myFeatureFlags)
        AppReveal.registerNetworkObservable(myNetworkClient)
        #endif
    }
}
```

`WKWebView` support works automatically on macOS as well. No extra bridge registration is required.

When the listener is ready, AppReveal prints a loopback URL and an authenticated session URL. You can also read them from `AppReveal.url`, `AppReveal.sessionURL`, and `AppReveal.sessionToken`.

### 2. Add Bonjour keys to `Info.plist`

AppReveal uses local network discovery in debug builds.

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>AppReveal uses the local network for debug MCP connections.</string>
<key>NSBonjourServices</key>
<array>
    <string>_appreveal._tcp</string>
</array>
```

### 3. Register SwiftUI controls when needed

AppKit controls with `accessibilityIdentifier` are discovered through the `NSView` hierarchy. For SwiftUI controls that do not expose reliable AppKit views or accessibility identifiers, use the same explicit registration modifier as iOS:

```swift
Button("Refresh") { refresh() }
#if DEBUG
.appReveal("orders.refresh", label: "Refresh", activate: refresh)
#endif
```

Registered SwiftUI controls appear in `get_elements` with `idSource: "appReveal"` and in `get_view_tree` as `SwiftUI.AppRevealElement`. `tap_element` and `tap_text` call the `activate:` closure when provided, then fall back to the recorded frame.

### 4. Add screen identity and accessibility identifiers

Screen identity is auto-derived from controller class names. Override it only when you want a stable custom key.

```swift
#if DEBUG
extension OrdersListViewController: ScreenIdentifiable {
    var screenKey: String { "orders.list" }
    var screenTitle: String { "Orders" }
}
#endif
```

```swift
searchField.accessibilityIdentifier = "orders.search"
refreshButton.accessibilityIdentifier = "orders.refresh"
```

### 5. Connect and use

```bash
# Discover the service
dns-sd -B _appreveal._tcp local.

# Check listener health. This endpoint is intentionally unauthenticated.
curl http://localhost:<port>/health

# Copy the token from the AppReveal log or AppReveal.sessionToken.
TOKEN="<session-token>"

# Initialize MCP session
curl -X POST http://localhost:<port>/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'

# List windows
curl -X POST http://localhost:<port>/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_windows","arguments":{}}}'
```

For LAN clients, resolve the Bonjour service host/port and include the same token via `Authorization: Bearer <token>` or `X-AppReveal-Session`. If `localhost` works but LAN discovery or reachability does not, check Local Network permission, firewall/VPN state, and `com.apple.security.network.server` for sandboxed apps.

The repository includes a repeatable check for listener health, authentication, and MCP initialization.
Pass the printed session URL; optionally pass the Mac's LAN hostname or IP to verify the same listener
from a non-loopback address:

```bash
scripts/verify-macos-lan-mcp.sh '<AppReveal.sessionURL>' [<lan-host-or-ip>]
```

For the strongest acceptance check, run that command from a second machine or use the Mac's LAN IP
from an Android Emulator shell. A valid run gets health `200`, unauthenticated MCP `401`, and
authenticated initialization `200` through the LAN address.

`GET /health` returns `bonjourDiagnostics` and `lan` objects. Use them when loopback works but remote LAN clients fail:

- `bonjour: "advertising"` means mDNS published successfully.
- `bonjour: "suppressed"` means AppReveal kept the HTTP listener running but did not advertise because no usable LAN interface/path was visible. Check `bonjourDiagnostics.suppressionReason`.
- `bonjour: "retrying"` or `"failed"` includes `lastError` and `lastErrorHint`; `-65555` is Bonjour `NoAuth`, usually Local Network permission or missing `NSBonjourServices`.
- `lan.interfaces` lists the process-visible IPv4/IPv6 interfaces and marks which ones are LAN candidates.

## Integration protocols

All protocol conformance should be wrapped in `#if DEBUG`.

```swift
protocol StateProviding: AnyObject {
    func snapshot() -> [String: AnyCodable]
}

protocol NavigationProviding: AnyObject {
    var currentRoute: String { get }
    var navigationStack: [String] { get }
    var presentedModals: [String] { get }
}

protocol FeatureFlagProviding: AnyObject {
    func allFlags() -> [String: AnyCodable]
}

protocol NetworkObservable: AnyObject {
    var recentRequests: [CapturedRequest] { get }
    func addObserver(_ observer: NetworkTrafficObserver)
}
```

## macOS-specific tools

| Tool | Description |
|------|-------------|
| `list_windows` | List visible app windows with IDs, titles, frames, and key status |
| `get_menu_bar` | Read the main menu hierarchy recursively |
| `click_menu_item` | Invoke a menu item by title path, for example `File > Save` |
| `focus_window` | Bring a specific window to the front and make it key |

## Multi-window support

All native UI tools and all WKWebView/DOM tools accept an optional `window_id` parameter. Get the ID from `list_windows`, then pass it to target a specific window. If you omit `window_id`, AppReveal uses the current key window.

## Security

- All code behind `#if DEBUG` -- zero production footprint
- Generated per-session token required for MCP POST requests
- Health diagnostics available at `GET /health`
- Loopback CORS only; LAN clients should use native MCP clients or explicit headers
- Local Network, firewall/VPN, and sandbox network permissions can affect LAN reachability
- Bonjour publish failures retry automatically; advertising is suppressed when no LAN candidate is visible
- Sensitive headers (Authorization, Cookie) redacted in network capture

## Platform details

- Transport: NWListener (Network.framework)
- Discovery: NetService (Bonjour/mDNS) publishing `_appreveal._tcp` after listener readiness and LAN diagnostics
- View hierarchy: NSView tree walking plus explicit SwiftUI `.appReveal(...)` registrations
- Screenshots: window snapshots
- WebView: WKWebView + evaluateJavaScript

## Example app

See [`example/macOS/AppRevealMacExample/`](../example/macOS/AppRevealMacExample/) for a macOS AppKit example with sidebar navigation, multi-window-aware tools, and curl verification steps.
