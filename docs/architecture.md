# AppReveal Architecture

## System overview

```
iOS App (debug build)                      macOS App (debug build)
 +-- AppReveal framework                    +-- AppReveal framework
 |    +-- MCPServer                         |    +-- MCPServer
 |    +-- BonjourDiscovery                  |    +-- BonjourDiscovery
 |    +-- IOSWindowProvider                 |    +-- MacOSWindowProvider
 |    +-- ScreenResolver                    |    +-- MacOSScreenResolver
 |    +-- ElementInventory                  |    +-- MacOSElementInventory
 |    +-- InteractionEngine                 |    +-- MacOSInteractionEngine
 |    +-- ScreenshotCapture                 |    +-- MacOSScreenshotCapture
 |    +-- WebViewBridge                     |    +-- MacOSWebViewBridge
 |    +-- NetworkObserver                   |    +-- NetworkObserver
 |    +-- NetworkMocker                     |    +-- NetworkMocker
 |    +-- StateBridge                       |    +-- StateBridge
 |    +-- DiagnosticsBridge                 |    +-- DiagnosticsBridge
 |    +-- DebugOverlay                      |    +-- DebugOverlay
 |
External Agent
 +-- Bonjour discovery (NWBrowser / dns-sd)
 +-- MCP client (Streamable HTTP)
 +-- LLM orchestration
```

## Transport

**Primary:** Streamable HTTP -- the MCP standard transport. Maximum compatibility with existing and future MCP clients.

**Discovery:** Bonjour/mDNS advertising as `_appreveal._tcp.local` with TXT records for app bundle ID, version, and capabilities.

## Module design

### MCPServer

Embedded HTTP server using `NWListener` on a dynamic port. Handles JSON-RPC MCP protocol messages. Binds only in debug builds.

- Serves tool metadata via `tools/list`
- Executes tool calls via `tools/call`
- Per-session token authentication
- Runs on main actor for UI access

### BonjourDiscovery

Wraps `NWListener.Service` to advertise the MCP endpoint. Publishes TXT metadata:

- `bundleId` -- app bundle identifier
- `version` -- app version
- `port` -- server port
- `transport` -- `streamable-http`

Requires `NSLocalNetworkUsageDescription` and `NSBonjourServices` in Info.plist.

### IOSWindowProvider / MacOSWindowProvider

Enumerates visible app windows and resolves the target window for tool execution.

- `list_windows` exposes stable IDs, titles, frames, and key-window state
- All UI and WKWebView tools accept optional `window_id`
- If `window_id` is omitted, the current key window is used

### ScreenResolver / MacOSScreenResolver

Determines the currently active screen using multiple signals:

1. Explicit `screenKey` from `ScreenIdentifiable` protocol conformance
2. UIKit/AppKit controller hierarchy (nav stack, tabs, split views, modals)
3. Route state from app-provided router
4. Presentation stack depth

Returns a `ScreenInfo` with key, title, framework type, controller chain, nav depth, confidence score, `source` (`"explicit"` or `"derived"`), and `appBarTitle` (extracted from navigation bar / toolbar / window title).

### ElementInventory / MacOSElementInventory

Enumerates visible interactive elements. Each element exposes:

- `id` (accessibility identifier, text-derived, or auto-generated)
- `type` (button, textField, toggle, etc.)
- `label`, `value`
- `enabled`, `visible`, `tappable`
- `frame` (CGRect in screen coordinates)
- `actions` (available interaction types)
- `idSource` — how the ID was derived: `"explicit"`, `"text"`, `"semantics"`, `"tooltip"`, `"derived"`

ID resolution cascade: explicit accessibility identifier → semantics (accessibility label / content description) → visible text (normalized to snake_case) → auto-generated derived ID. Duplicate IDs are disambiguated with `_1`, `_2`, etc.

Text-based element lookup via `tap_text` walks the view hierarchy for matching visible text, then resolves the nearest tappable ancestor (UIControl, NSControl, gesture-recognizer-bearing view, table/collection cell).

Walks the UIKit or AppKit view hierarchy for the selected window. SwiftUI elements are accessed through their hosting layer and accessibility identifiers.

### InteractionEngine / MacOSInteractionEngine

Executes UI actions on the main thread:

- `tap(elementId:)` / `tap(point:)`
- `type(text:, elementId:)`
- `clear(elementId:)`
- `scroll(direction:, containerId:)`
- `scrollTo(elementId:)`
- `navigateBack()` / `dismissModal()`

Uses platform-native event dispatch and direct view/control method calls. Scroll uses `UIScrollView.setContentOffset` on iOS and `NSScrollView` APIs on macOS.

### ScreenshotCapture / MacOSScreenshotCapture

Captures the current window using `UIGraphicsImageRenderer` on iOS and window snapshots on macOS. Returns PNG or JPEG data with metadata (dimensions, scale).

Optional element-level cropping by accessibility identifier.

### WebViewBridge / MacOSWebViewBridge

Discovers `WKWebView` instances inside the selected window and powers the DOM tools.

- Auto-discovers web views from the native view hierarchy
- Evaluates JavaScript for DOM inspection and interaction
- Shares the same tool surface on iOS and macOS, with `window_id` support on every tool

### NetworkObserver

Hooks into app networking to capture traffic:

- Integrates with app's network client via `NetworkObservable` protocol
- Records `URLSessionTaskMetrics` for timing data
- Stores recent requests/responses in a ring buffer
- Correlates errors with specific calls

### NetworkMocker

Injects mock responses via `URLProtocol` registered on the app's `URLSessionConfiguration`:

- Mock specific URL patterns with custom responses
- Simulate latency, timeouts, offline state
- Simulate HTTP error codes
- Bypass mocks for specific requests

### StateBridge

Reads app-owned state through protocols:

- `StateProviding` -- snapshot of app state as `[String: Any]`
- `NavigationProviding` -- current route, nav stack, modal state
- `FeatureFlagProviding` -- active feature flags
- Optional: controlled state mutation in debug mode

### DiagnosticsBridge

Aggregates diagnostic data:

- Recent logs via `OSLogStore` queries
- MetricKit payload summaries
- App-captured errors and assertions
- Memory/CPU snapshots

### DebugOverlay

Optional in-app floating panel showing:

- Server status (port, discovery name, connected clients)
- Recent tool calls with timing
- Recent network calls
- Current screen identity
- Manual command input for testing without an external client

## Key protocols

```swift
/// Conform screens to provide stable identity
protocol ScreenIdentifiable {
    var screenKey: String { get }
    var screenTitle: String { get }
    var debugMetadata: [String: Any] { get }
}

/// Conform your network client to expose traffic
protocol NetworkObservable {
    var recentRequests: [CapturedRequest] { get }
    func addObserver(_ observer: NetworkTrafficObserver)
}

/// Conform your app state container
protocol StateProviding {
    func snapshot() -> [String: AnyCodable]
}

/// Conform your router/coordinator
protocol NavigationProviding {
    var currentRoute: String { get }
    var navigationStack: [String] { get }
    var presentedModals: [String] { get }
}

/// Conform your feature flag system
protocol FeatureFlagProviding {
    func allFlags() -> [String: AnyCodable]
}
```

## MCP tools (v1)

### UI / Navigation
| Tool | Description |
|------|-------------|
| `list_windows` | List visible app windows and their IDs |
| `get_screen` | Current screen identity and metadata |
| `get_elements` | Visible interactive elements |
| `tap_element` | Tap by accessibility identifier |
| `tap_text` | Tap by visible text content |
| `tap_point` | Tap by screen coordinates |
| `type_text` | Type into focused or specified field |
| `clear_text` | Clear a text field |
| `scroll` | Scroll a container by direction |
| `scroll_to_element` | Scroll until element is visible |
| `screenshot` | Capture screen or element image |

### State
| Tool | Description |
|------|-------------|
| `get_state` | App state snapshot |
| `get_navigation_stack` | Current navigation state |
| `get_feature_flags` | Active feature flags |

### Network
| Tool | Description |
|------|-------------|
| `get_network_calls` | Recent HTTP traffic |
| `get_network_call_detail` | Full request/response for a call |
| `mock_network_response` | Inject mock response for URL pattern |
| `simulate_latency` | Add artificial delay |
| `simulate_timeout` | Force timeout on matching requests |
| `disable_network` | Simulate offline state |

### Diagnostics
| Tool | Description |
|------|-------------|
| `get_logs` | Recent app logs |
| `get_recent_errors` | Recent errors and assertions |
| `get_metrics_summary` | MetricKit performance summary |

### App Control
| Tool | Description |
|------|-------------|
| `launch_context` | App launch environment info |
| `open_deeplink` | Navigate via deep link URL |
| `reset_app_state` | Clear app state for clean testing |

All UI and WKWebView tools accept an optional `window_id` parameter from `list_windows`. If omitted, AppReveal targets the current key window.

### macOS only
| Tool | Description |
|------|-------------|
| `get_menu_bar` | Read the app menu bar hierarchy |
| `click_menu_item` | Invoke a menu item by title path |
| `focus_window` | Bring a window to the front and make it key |

## Security model

- All code wrapped in `#if DEBUG` -- zero production footprint
- `NWListener` binds to local network only
- Optional pairing token displayed in DebugOverlay
- Sensitive fields (auth tokens, passwords) redacted in network capture
- State mutation tools require explicit opt-in registration
- Service hidden until `AppReveal.start()` is called

## Swift Package structure

```
iOS/                                   (single Swift package for iOS + macOS)
 +-- Package.swift
 +-- Sources/
 |    +-- AppReveal/
 |    |    +-- AppReveal.swift            (public entry point)
 |    |    +-- MCPServer/
 |    |    |    +-- MCPServer.swift
 |    |    |    +-- MCPRouter.swift
 |    |    |    +-- MCPMessage.swift
 |    |    |    +-- MacOSMCPTools.swift
 |    |    +-- Discovery/
 |    |    |    +-- BonjourAdvertiser.swift
 |    |    +-- Window/
 |    |    |    +-- WindowProvider.swift
 |    |    |    +-- WindowRef.swift
 |    |    |    +-- IOSWindowProvider.swift
 |    |    |    +-- MacOSWindowProvider.swift
 |    |    +-- Screen/
 |    |    |    +-- ScreenResolver.swift
 |    |    |    +-- MacOSScreenResolver.swift
 |    |    |    +-- ScreenIdentifiable.swift
 |    |    +-- Elements/
 |    |    |    +-- ElementInventory.swift
 |    |    |    +-- MacOSElementInventory.swift
 |    |    |    +-- ElementInfo.swift
 |    |    +-- Interaction/
 |    |    |    +-- InteractionEngine.swift
 |    |    |    +-- MacOSInteractionEngine.swift
 |    |    +-- Screenshot/
 |    |    |    +-- ScreenshotCapture.swift
 |    |    |    +-- MacOSScreenshotCapture.swift
 |    |    +-- Network/
 |    |    |    +-- NetworkObserver.swift
 |    |    |    +-- NetworkMocker.swift
 |    |    |    +-- CapturedRequest.swift
 |    |    +-- WebView/
 |    |    |    +-- WebViewBridge.swift
 |    |    |    +-- MacOSWebViewBridge.swift
 |    |    |    +-- WebViewTools.swift
 |    |    |    +-- DOMSerializer.swift
 |    |    +-- State/
 |    |    |    +-- StateBridge.swift
 |    |    |    +-- NavigationProviding.swift
 |    |    |    +-- FeatureFlagProviding.swift
 |    |    +-- Diagnostics/
 |    |    |    +-- DiagnosticsBridge.swift
 |    |    +-- Overlay/
 |    |    |    +-- DebugOverlay.swift
 |    |    +-- Shared/
 |    |         +-- AnyCodable.swift
 |    +-- AppRevealClient/               (optional companion for agents)
 |         +-- AppRevealClient.swift
 |         +-- BonjourBrowser.swift
 +-- Tests/
      +-- AppRevealTests/
```

## Design principles

1. **Convention over configuration** -- works with minimal setup if naming conventions are followed
2. **Explicit over magic** -- no private API usage, no SwiftUI internal tree walking
3. **Read-first** -- observation tools before mutation tools
4. **Debug-only** -- zero production impact, compile-time guarantee
5. **Standard transport** -- MCP Streamable HTTP for maximum client compatibility
