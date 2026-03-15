# AppReveal

Debug-only in-app MCP server for iOS. Lets LLM agents discover, inspect, and control native apps over the local network -- like Playwright for native, but with direct access to app state, navigation, network traffic, and diagnostics.

## How it works

```
Your App (debug build)                    External Agent
 +-- AppReveal framework                   +-- Bonjour browse for _appreveal._tcp
      +-- MCP Server (Streamable HTTP)  <---+-- MCP client (curl, SDK, Claude, etc.)
      +-- Bonjour advertisement             +-- LLM orchestration
      +-- Screen/element/state bridges
```

1. App calls `AppReveal.start()` in a debug build
2. Framework starts an HTTP server on a dynamic port
3. Bonjour advertises the service as `_appreveal._tcp` on the LAN
4. Agent discovers the service, connects, and calls MCP tools

## Quick start

### 1. Add the package

Add `iOS/` as a local Swift package dependency (or point to the repo).

### 2. Start the server

```swift
#if DEBUG
import AppReveal
#endif

func application(_ application: UIApplication, didFinishLaunchingWithOptions ...) -> Bool {
    #if DEBUG
    AppReveal.start()

    // Register providers for deeper inspection
    AppReveal.registerStateProvider(myStateContainer)
    AppReveal.registerNavigationProvider(myRouter)
    AppReveal.registerFeatureFlagProvider(myFeatureFlags)
    AppReveal.registerNetworkObservable(myNetworkClient)
    #endif
    return true
}
```

### 3. Add screen identity

```swift
#if DEBUG
extension LoginViewController: ScreenIdentifiable {
    var screenKey: String { "auth.login" }
    var screenTitle: String { "Login" }
    var debugMetadata: [String: Any] { [:] }
}
#endif
```

### 4. Add accessibility identifiers

```swift
emailField.accessibilityIdentifier = "login.email"
passwordField.accessibilityIdentifier = "login.password"
loginButton.accessibilityIdentifier = "login.submit"
```

### 5. Connect and use

```bash
# Discover the service
dns-sd -B _appreveal._tcp local.
dns-sd -L "AppReveal-com.yourapp" _appreveal._tcp local.
# => dictator.local.:56209

# Initialize MCP session
curl -X POST http://localhost:56209/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'

# Get current screen
curl -X POST http://localhost:56209/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_screen","arguments":{}}}'
# => {"screenKey":"auth.login","confidence":1,"controllerChain":["LoginViewController"],...}

# List interactive elements
curl -X POST http://localhost:56209/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_elements","arguments":{}}}'
# => [{"id":"login.email","type":"textField","actions":"tap,type,clear"}, ...]

# Type into a field
curl -X POST http://localhost:56209/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"type_text","arguments":{"text":"user@test.com","element_id":"login.email"}}}'

# Tap a button
curl -X POST http://localhost:56209/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"tap_element","arguments":{"element_id":"login.submit"}}}'

# Take a screenshot (returns base64 PNG)
curl -X POST http://localhost:56209/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"screenshot","arguments":{}}}'
```

## MCP tools

### UI and navigation

| Tool | Description |
|------|-------------|
| `get_screen` | Current screen identity, controller chain, confidence score |
| `get_elements` | All visible interactive elements with id, type, frame, actions |
| `tap_element` | Tap by accessibility identifier (buttons, cells, controls) |
| `tap_point` | Tap at screen coordinates |
| `type_text` | Type text into a field (by element ID or current responder) |
| `clear_text` | Clear a text field |
| `scroll` | Scroll a container (up/down/left/right) |
| `scroll_to_element` | Scroll until an element is visible |
| `screenshot` | Capture screen or element as base64 PNG/JPEG |
| `select_tab` | Switch tab bar tabs by index |
| `navigate_back` | Pop the navigation stack |
| `dismiss_modal` | Dismiss the topmost modal |
| `open_deeplink` | Open a URL in the app |

### State and diagnostics

| Tool | Description |
|------|-------------|
| `get_state` | App state snapshot (login, user, cart, etc.) |
| `get_navigation_stack` | Current route, nav stack, modal stack |
| `get_feature_flags` | All active feature flags |
| `get_network_calls` | Recent HTTP traffic with method, URL, status, duration |
| `get_logs` | Recent app logs from OSLog |
| `get_recent_errors` | Recent captured errors |
| `launch_context` | Bundle ID, version, device model, OS version |

## Integration protocols

All protocol conformance should be wrapped in `#if DEBUG`.

```swift
/// Expose app state
protocol StateProviding: AnyObject {
    func snapshot() -> [String: AnyCodable]
}

/// Expose navigation state
protocol NavigationProviding: AnyObject {
    var currentRoute: String { get }
    var navigationStack: [String] { get }
    var presentedModals: [String] { get }
}

/// Expose feature flags
protocol FeatureFlagProviding: AnyObject {
    func allFlags() -> [String: AnyCodable]
}

/// Expose network traffic
protocol NetworkObservable: AnyObject {
    var recentRequests: [CapturedRequest] { get }
    func addObserver(_ observer: NetworkTrafficObserver)
}
```

## Naming conventions

| Thing | Pattern | Examples |
|-------|---------|----------|
| Screen keys | `section.screen` | `auth.login`, `orders.detail`, `settings.main` |
| Element IDs | `screen.element` | `login.email`, `login.submit`, `orders.cell_0` |

## Why this beats screenshot-only automation

AppReveal gives agents structured data instead of pixels:

- **Exact screen identity** with confidence scores, not guessing from screenshots
- **Machine-addressable elements** with types, states, and available actions
- **App state** read directly -- login status, feature flags, cart contents
- **Navigation state** -- current route, stack depth, presented modals
- **Network traffic** -- every API call with method, URL, status, timing
- **Deterministic interactions** -- tap by ID, not by fragile coordinates

## Example app

See [`example/iOS/`](example/iOS/) for a full example app with 10 screens, 60+ identified elements, and all framework features integrated. Run it on a simulator and connect via curl to test every tool.

## Platforms

| Platform | Status |
|----------|--------|
| iOS | Working (Phase 1-3 tools functional) |
| Android | Planned |

## Security

- All code behind `#if DEBUG` -- zero production footprint
- Local network only (NWListener)
- Sensitive headers (Authorization, Cookie) redacted in network capture
- No state mutation without explicit opt-in

## Documentation

- [Architecture](docs/architecture.md) -- module design, protocols, package structure
- [Build Brief](docs/brief.md) -- phased implementation plan with task tracking

## Requirements

- iOS 16.0+
- Swift 5.9+
- Xcode 15+
