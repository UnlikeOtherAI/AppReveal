# AppReveal -- macOS

## Requirements

- macOS 13.0+
- Swift 5.9+
- Xcode 15+

## Installation

### Swift Package Manager

Use the same package as iOS. AppReveal ships as a single Swift package with iOS and macOS platform support.

```swift
.package(url: "https://github.com/UnlikeOtherAI/AppReveal.git", from: "0.4.0")
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

### 3. Add screen identity and accessibility identifiers

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

### 4. Connect and use

```bash
# Discover the service
dns-sd -B _appreveal._tcp local.

# Initialize MCP session
curl -X POST http://localhost:<port>/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'

# List windows
curl -X POST http://localhost:<port>/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_windows","arguments":{}}}'
```

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
- Local network only (NWListener)
- Sensitive headers (Authorization, Cookie) redacted in network capture

## Platform details

- Transport: NWListener (Network.framework)
- Discovery: NWListener.Service (Bonjour/mDNS)
- View hierarchy: NSView tree walking
- Screenshots: window snapshots
- WebView: WKWebView + evaluateJavaScript

## Example app

See [`example/macOS/AppRevealMacExample/`](../example/macOS/AppRevealMacExample/) for a macOS AppKit example with sidebar navigation, multi-window-aware tools, and curl verification steps.
