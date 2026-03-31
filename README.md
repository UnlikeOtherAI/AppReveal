# AppReveal

<img src="icon_180.png" width="180" alt="AppReveal icon" />

**[unlikeotherai.github.io/AppReveal](https://unlikeotherai.github.io/AppReveal/)**

Debug-only in-app MCP server for iOS, macOS, Android, Flutter, and React Native. Lets LLM agents discover, inspect, and control native apps over the local network -- like Playwright for native, but with direct access to app state, navigation, network traffic, DOM, and diagnostics.

## How it works

```
Your App (debug build)                    External Agent
 +-- AppReveal framework                   +-- mDNS browse for _appreveal._tcp
      +-- MCP Server (Streamable HTTP)  <---+-- MCP client (curl, SDK, Claude, etc.)
      +-- mDNS advertisement               +-- LLM orchestration
      +-- Screen/element/state bridges
      +-- WebView DOM bridge
```

1. App calls `AppReveal.start()` in a debug build
2. Framework starts an HTTP server on a dynamic port
3. mDNS advertises the service as `_appreveal._tcp` on the LAN
4. Agent discovers the service, connects, and calls MCP tools

AppReveal shares the same core MCP surface across platforms. macOS adds desktop-specific window and menu tools on top of the shared native and web view tools.

## Quick start

### iOS

```swift
// Package.swift
.package(url: "https://github.com/UnlikeOtherAI/AppReveal.git", from: "0.8.0")
```

```swift
#if DEBUG
AppReveal.start()
#endif
```

See [iOS guide](docs/ios.md) for full setup.

### macOS

```swift
// Package.swift
.package(url: "https://github.com/UnlikeOtherAI/AppReveal.git", from: "0.8.0")
```

```swift
#if DEBUG
AppReveal.start()
#endif
```

See [macOS guide](docs/macos.md) for full setup.

### Android

```kotlin
// build.gradle.kts
debugImplementation("com.appreveal:appreveal")
releaseImplementation("com.appreveal:appreveal-noop")
```

```kotlin
if (BuildConfig.DEBUG) {
    AppReveal.start(this)
}
```

See [Android guide](docs/android.md) for full setup.

### Flutter

```dart
// pubspec.yaml
dependencies:
  appreveal:
    path: Flutter/appreveal
```

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppReveal.start(); // no-ops in release builds
  runApp(AppReveal.wrap(const MyApp()));
}

// In MaterialApp:
MaterialApp(
  navigatorObservers: [AppReveal.navigatorObserver],
  ...
)
```

See [Flutter guide](Flutter/README.md) for full setup.

### React Native

```sh
npm install react-native-appreveal
cd ios && pod install
```

```tsx
import { AppReveal, AppRevealFetchInterceptor } from 'react-native-appreveal';

if (__DEV__) {
  AppReveal.start();
  AppRevealFetchInterceptor.install();
}
```

See [React Native guide](ReactNative/README.md) for full setup.

## MCP tools

### UI and navigation

| Tool | Description |
|------|-------------|
| `list_windows` | List visible app windows and their IDs |
| `get_screen` | Current screen identity, controller/activity chain, confidence score |
| `get_elements` | All visible interactive elements with id, type, frame, actions |
| `get_view_tree` | Full view hierarchy with class, frame, properties, accessibility info |
| `tap_element` | Tap by element identifier (buttons, cells, controls) |
| `tap_text` | Tap by visible text content (finds text, walks to tappable ancestor) |
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

All native UI tools and all web view tools accept an optional `window_id` parameter from `list_windows`. If omitted, AppReveal targets the current key window.

### macOS desktop tools

| Tool | Description |
|------|-------------|
| `get_menu_bar` | Read the app menu bar hierarchy |
| `click_menu_item` | Invoke a menu item by title path |
| `focus_window` | Bring a specific window to the front and make it key |

### State and diagnostics

| Tool | Description |
|------|-------------|
| `get_state` | App state snapshot (login, user, cart, etc.) |
| `get_navigation_stack` | Current route, nav stack, modal stack |
| `get_feature_flags` | All active feature flags |
| `get_network_calls` | Recent HTTP traffic with method, URL, status, duration |
| `get_logs` | Recent app logs |
| `get_recent_errors` | Recent captured errors |
| `launch_context` | App ID, version, device model, OS version |
| `device_info` | Full device snapshot: Info.plist / manifest metadata, hardware, OS build, screen metrics, locale, timezone, battery, memory, storage, declared permissions |

### WebView -- DOM access

iOS/macOS/Android: auto-discovers WebViews from the view hierarchy. Flutter: register via `AppReveal.registerWebView(id, controller)`.

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

### WebView -- token-efficient queries

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

## Naming conventions

| Thing | Pattern | Examples |
|-------|---------|----------|
| Screen keys | `section.screen` | `auth.login`, `orders.detail`, `settings.main` |
| Element IDs | `screen.element` | `login.email`, `login.submit`, `orders.cell_0` |

Element IDs map to platform-specific mechanisms:

| Platform | Mechanism |
|----------|-----------|
| iOS | `view.accessibilityIdentifier` |
| macOS | `view.accessibilityIdentifier()` |
| Android | `view.tag` or resource entry name |
| Flutter | `ValueKey<String>` on the widget |

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

## Platforms

| Platform | Status | Tools |
|----------|--------|-------|
| iOS | Working | Shared native + web view tool surface |
| macOS | Working | Shared native + web view tools plus menu/window tools |
| Android | Working | Shared native + web view tool surface |
| Flutter | Working | Shared native + web view tool surface |
| React Native | Working | Shared native + web view tool surface |

## Example apps

- [iOS example](example/iOS/) -- 11 screens, 60+ elements, all framework features
- [macOS example](example/macOS/AppRevealMacExample/) -- AppKit desktop example with sidebar navigation and curl verification
- [Android example](example/Android/) -- 11 screens matching the iOS example
- [Flutter example](Flutter/example/) -- 11 screens matching iOS and Android
- [React Native example](ReactNative/example/) -- 8 screens, React Navigation v7

## CLI

There is now a dedicated AppReveal CLI in [CLI/README.md](/System/Volumes/Data/.internal/projects/Projects/AppReveal/CLI/README.md) for discovering `_appreveal._tcp` services, listing available MCP tools, and sending MCP requests without hand-written `dns-sd` and `curl` calls.
Install it with `npm install -g @unlikeotherai/appreveal`.

## Security

- **iOS**: All code behind `#if DEBUG` -- zero production footprint
- **macOS**: All code behind `#if DEBUG` -- zero production footprint
- **Android**: Added as `debugImplementation` -- not included in release APK
- **Flutter**: `kReleaseMode` check in `AppReveal.start()` -- zero code paths execute in release
- **React Native**: `__DEV__` guard -- all methods are no-ops in production builds
- Local network only
- Sensitive headers (Authorization, Cookie) redacted in network capture
- No state mutation without explicit opt-in

## Documentation

- [iOS guide](docs/ios.md) -- installation, setup, protocols
- [macOS guide](docs/macos.md) -- installation, setup, protocols, multi-window notes
- [Android guide](docs/android.md) -- installation, setup, interfaces
- [Flutter guide](Flutter/README.md) -- installation, setup, integration patterns
- [React Native guide](ReactNative/README.md) -- installation, setup, integration patterns
- [Architecture](docs/architecture.md) -- module design, protocols, package structure
- [Tools reference](docs/tools.md) -- tool parameters and response shapes
- [Build Brief](docs/brief.md) -- phased implementation plan
- [WKWebView Support](docs/wkwebview-support.md) -- iOS DOM access design doc

## License

MIT
