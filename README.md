# AppReveal

Debug-only in-app MCP server for iOS. Lets LLM agents discover, inspect, and control native apps over the local network -- like Playwright for native, but with direct access to app state, navigation, network traffic, DOM, and diagnostics.

## How it works

```
Your App (debug build)                    External Agent
 +-- AppReveal framework                   +-- Bonjour browse for _appreveal._tcp
      +-- MCP Server (Streamable HTTP)  <---+-- MCP client (curl, SDK, Claude, etc.)
      +-- Bonjour advertisement             +-- LLM orchestration
      +-- Screen/element/state bridges
      +-- WKWebView DOM bridge
```

1. App calls `AppReveal.start()` in a debug build
2. Framework starts an HTTP server on a dynamic port
3. Bonjour advertises the service as `_appreveal._tcp` on the LAN
4. Agent discovers the service, connects, and calls MCP tools

## Quick start

### 1. Add the package

```swift
.package(url: "https://github.com/UnlikeOtherAI/AppReveal.git", from: "0.2.0")
```

### 2. Start the server

```swift
#if DEBUG
import AppReveal
#endif

func application(_ application: UIApplication, didFinishLaunchingWithOptions ...) -> Bool {
    #if DEBUG
    AppReveal.start()

    // Optional: register providers for deeper inspection
    AppReveal.registerStateProvider(myStateContainer)
    AppReveal.registerNavigationProvider(myRouter)
    AppReveal.registerFeatureFlagProvider(myFeatureFlags)
    AppReveal.registerNetworkObservable(myNetworkClient)
    #endif
    return true
}
```

That's it. WKWebView support works automatically -- no additional integration needed.

### 3. Add screen identity (optional)

Screen identity is auto-derived from class names -- `LoginViewController` becomes key `"login"`, title `"Login"`. Override only when you want a custom key:

```swift
#if DEBUG
extension LoginViewController: ScreenIdentifiable {
    var screenKey: String { "auth.login" }
    var screenTitle: String { "Login" }
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

# Fill a form and submit in one call
curl -X POST http://localhost:56209/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"batch","arguments":{"actions":[
    {"tool":"type_text","arguments":{"element_id":"login.email","text":"user@test.com"}},
    {"tool":"type_text","arguments":{"element_id":"login.password","text":"secret"}},
    {"tool":"tap_element","arguments":{"element_id":"login.submit"}},
    {"tool":"get_screen","arguments":{},"delay_ms":1000}
  ]}}}'
```

## MCP tools (43 total)

### UI and navigation

| Tool | Description |
|------|-------------|
| `get_screen` | Current screen identity, controller chain, confidence score |
| `get_elements` | All visible interactive elements with id, type, frame, actions |
| `get_view_tree` | Full view hierarchy with class, frame, properties, accessibility info |
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

### WKWebView -- DOM access

Auto-discovers any WKWebView on screen. No integration code needed.

| Tool | Description |
|------|-------------|
| `get_webviews` | List all web views with URL, title, loading state |
| `get_dom_tree` | Full or partial DOM tree (with `root`, `max_depth`, `visible_only` params) |
| `get_dom_interactive` | All inputs, buttons, links, selects with selectors and attributes |
| `query_dom` | CSS selector query -- returns matching elements |
| `find_dom_text` | Find elements by text content |
| `web_click` | Click a DOM element by CSS selector |
| `web_type` | Type into input/textarea (React/Vue/Angular compatible) |
| `web_select` | Select a dropdown option |
| `web_toggle` | Check/uncheck a checkbox or radio |
| `web_scroll_to` | Scroll to a DOM element |
| `web_evaluate` | Run arbitrary JavaScript |
| `web_navigate` | Navigate to a URL |
| `web_back` | Go back in web view history |
| `web_forward` | Go forward in web view history |

### WKWebView -- token-efficient queries

Purpose-built tools that return only what you need, saving tokens.

| Tool | Description |
|------|-------------|
| `get_dom_summary` | Page overview: title, meta, headings, element counts, form structure |
| `get_dom_text` | Visible text content stripped of all markup (optional CSS selector scope) |
| `get_dom_links` | All links -- just text and href |
| `get_dom_forms` | All forms with fields, types, values, options, selectors |
| `get_dom_headings` | All h1-h6 for page structure |
| `get_dom_images` | All images with src, alt, dimensions |
| `get_dom_tables` | All tables with headers and row data |

### Batch operations

| Tool | Description |
|------|-------------|
| `batch` | Execute multiple tools in one call. Supports `delay_ms` per action for animations/transitions and `stop_on_error`. Works with all native and web tools. |

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
- **DOM access** -- full web view inspection and interaction, no extra setup
- **Batch operations** -- fill forms, navigate screens, verify state in one call
- **Deterministic interactions** -- tap by ID or CSS selector, not by fragile coordinates

## Example app

See [`example/iOS/`](example/iOS/) for a full example app with 11 screens (including a WKWebView demo), 60+ identified elements, and all framework features integrated. Run it on a simulator and connect via curl to test every tool.

## Platforms

| Platform | Status |
|----------|--------|
| iOS | Working -- 43 tools, native + web view |
| Android | Planned |

## Security

- All code behind `#if DEBUG` -- zero production footprint
- Local network only (NWListener)
- Sensitive headers (Authorization, Cookie) redacted in network capture
- No state mutation without explicit opt-in

## Documentation

- [Architecture](docs/architecture.md) -- module design, protocols, package structure
- [Build Brief](docs/brief.md) -- phased implementation plan with task tracking
- [WKWebView Support](docs/wkwebview-support.md) -- design doc for DOM access

## Requirements

- iOS 16.0+
- Swift 5.9+
- Xcode 15+

## License

MIT
