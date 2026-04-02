# MCP Tools Reference

49 tools are available across all platforms (iOS, macOS, Android, Flutter, React Native). The shared tool surface (native UI, state, network, diagnostics, WebView DOM) is identical on every platform. macOS adds 3 desktop-specific tools and all native UI/WebView tools accept an optional `window_id` parameter for multi-window targeting.

### `list_windows`
List visible app windows with stable IDs. Use the returned `window_id` to target a specific window in any UI or WebView tool. If `window_id` is omitted, the key window is used.

**Parameters:** none

**Response:**
```json
{
  "windows": [
    {
      "id": "main_window",
      "title": "AppReveal Mac Example",
      "frame": "0,0,1280,800",
      "isKey": true
    }
  ]
}
```

---

## UI and Navigation

### `get_screen`
Get the currently active screen identity and metadata.

**Parameters:** none

**Response:**
```json
{
  "screenKey": "auth.login",
  "screenTitle": "Login",
  "frameworkType": "uikit",
  "controllerChain": ["MainTabBarController", "LoginViewController"],
  "activeTab": "UINavigationController",
  "navigationDepth": 0,
  "presentedModals": [],
  "confidence": 1.0,
  "source": "explicit",
  "appBarTitle": "Login"
}
```

- `source` — `"explicit"` (from `ScreenIdentifiable` conformance) or `"derived"` (auto-detected from controller/activity class name)
- `appBarTitle` — title extracted from the navigation bar (iOS), window title (macOS), or toolbar/action bar (Android). `null` if none found.

---

### `get_elements`
List all visible interactive elements on the current screen.

**Parameters:** none

**Response:**
```json
{
  "screenKey": "auth.login",
  "elements": [
    {
      "id": "login.email",
      "type": "textField",
      "label": "",
      "value": "",
      "enabled": "true",
      "visible": "true",
      "tappable": "true",
      "frame": "32,364,338,34",
      "safeAreaInsets": { "top": 0, "leading": 0, "bottom": 0, "trailing": 0 },
      "safeAreaLayoutGuideFrame": { "x": 32, "y": 364, "width": 338, "height": 34 },
      "actions": "tap,type,clear",
      "idSource": "explicit"
    }
  ]
}
```

- `idSource` — how the element's `id` was derived: `"explicit"` (accessibility identifier / tag / resource ID), `"text"` (from visible text), `"semantics"` (accessibility label / content description), `"tooltip"`, or `"derived"` (auto-generated fallback)
- `safeAreaInsets` — per-view safe area insets using `leading` / `trailing` instead of physical `left` / `right`
- `safeAreaLayoutGuideFrame` — the view's safe area layout guide frame in screen coordinates
- Platform mapping: iOS/macOS use native safe areas, Android uses system bar/display-cutout insets, Flutter uses the nearest `MediaQuery.padding`

Element types: `button`, `textField`, `label`, `image`, `toggle`, `slider`, `scrollView`, `tableView`, `collectionView`, `cell`, `navigationBar`, `tabBar`, `other`

---

### `get_view_tree`
Dump the full view hierarchy with class, frame, properties, and accessibility info.

**Parameters:**
- `max_depth` (integer, optional) — default 50

**Response:**
```json
{
  "views": [...],
  "count": 142
}
```

Each node includes `safeAreaInsets` and `safeAreaLayoutGuideFrame` alongside the existing `frame` string so layout issues can be traced through the view hierarchy on every platform.

---

### `screenshot`
Capture the screen or a single element as base64-encoded image.

**Parameters:**
- `element_id` (string, optional) — capture just this element
- `format` (string, optional) — `"png"` (default) or `"jpeg"`

**Response:**
```json
{
  "image": "<base64>",
  "width": 1206,
  "height": 2622,
  "scale": 3.0,
  "format": "png"
}
```

---

### `tap_element`
Tap an element by its identifier.

**Parameters:**
- `element_id` (string, required)

**Response:** `{ "success": true, "element_id": "login.submit" }`

---

### `tap_text`
Tap an element by its visible text content. Finds text in the view hierarchy and walks up to the nearest tappable ancestor. Useful when elements lack accessibility identifiers.

**Parameters:**
- `text` (string, required) — text to find
- `match_mode` (string, optional) — `"exact"` (default) or `"contains"`
- `occurrence` (integer, optional) — 0-based index when multiple matches exist (default 0)

**Response:** `{ "success": true, "tapped_text": "Submit Order" }`

If multiple matches are found and `occurrence` is not specified, returns an error with candidates:
```json
{
  "error": "Multiple elements match 'Submit'. Use occurrence parameter to disambiguate.",
  "candidates": ["Submit Order", "Submit Review"]
}
```

---

### `tap_point`
Tap at specific screen coordinates.

**Parameters:**
- `x` (number, required)
- `y` (number, required)

**Response:** `{ "success": true }`

---

### `type_text`
Type text into a field.

**Parameters:**
- `text` (string, required)
- `element_id` (string, optional) — target field; uses current focus if omitted

**Response:** `{ "success": true, "text": "hello@example.com" }`

---

### `clear_text`
Clear a text field.

**Parameters:**
- `element_id` (string, required)

**Response:** `{ "success": true }`

---

### `scroll`
Scroll a container in a direction.

**Parameters:**
- `direction` (string, required) — `"up"`, `"down"`, `"left"`, `"right"`
- `container_id` (string, optional) — scroll a specific container; uses first scrollable if omitted

**Response:** `{ "success": true }`

---

### `scroll_to_element`
Scroll until an element is visible.

**Parameters:**
- `element_id` (string, required)

**Response:** `{ "success": true }`

---

### `select_tab`
Switch to a tab bar tab by zero-based index.

**Parameters:**
- `index` (integer, required)

**Response:** `{ "success": true, "tab_index": 2 }`

---

### `navigate_back`
Pop the current navigation stack.

**Parameters:** none

**Response:** `{ "success": true }`

---

### `dismiss_modal`
Dismiss the topmost modal or sheet.

**Parameters:** none

**Response:** `{ "success": true }`

---

### `open_deeplink`
Open a URL in the app.

**Parameters:**
- `url` (string, required)

**Response:** `{ "success": true, "url": "myapp://order/123" }`

---

## State and Diagnostics

### `get_state`
App state snapshot (whatever the app registers via `StateProviding` / `registerStateProvider`).

**Parameters:** none

**Response:** `{ "isLoggedIn": true, "cartCount": 3, ... }`

---

### `get_navigation_stack`
Current route, full navigation stack, and presented modals.

**Parameters:** none

**Response:**
```json
{
  "currentRoute": "orders.list",
  "navigationStack": ["orders.list", "catalog.list"],
  "presentedModals": []
}
```

---

### `get_feature_flags`
All active feature flags registered by the app.

**Parameters:** none

**Response:** `{ "newCheckout": true, "darkMode": false, ... }`

---

### `get_network_calls`
Recent HTTP traffic captured by the app.

**Parameters:**
- `limit` (integer, optional) — default 50, max 200

**Response:**
```json
{
  "calls": [
    {
      "id": "abc123",
      "method": "GET",
      "url": "https://api.example.com/orders",
      "statusCode": 200,
      "requestTimestamp": 1700000000000,
      "responseTimestamp": 1700000000320,
      "requestHeaders": { "Authorization": "[REDACTED]" },
      "responseBodySize": 1024
    }
  ]
}
```

Sensitive headers (`Authorization`, `Cookie`, `Set-Cookie`, `x-api-key`, `x-auth-token`) are automatically redacted.

---

### `get_logs`
Recent app log output.

**Parameters:**
- `subsystem` (string, optional) — filter by log subsystem (iOS only)
- `limit` (integer, optional) — number of entries

**Response:** `{ "logs": [{ "timestamp": "...", "level": "info", "message": "..." }] }`

---

### `get_recent_errors`
Recent errors captured via `AppReveal.captureError()` / `DiagnosticsBridge.captureError()`.

**Parameters:** none

**Response:** `{ "errors": [{ "domain": "NetworkError", "message": "...", "stackTrace": "..." }] }`

---

### `launch_context`
Basic app launch environment: bundle ID, version, device, OS.

**Parameters:** none

**Response:**
```json
{
  "bundleId": "com.example.app",
  "version": "2.1.0",
  "build": "42",
  "platform": "iOS",
  "systemVersion": "18.2",
  "deviceModel": "iPhone",
  "deviceName": "iPhone 16 Pro"
}
```

---

### `device_info`
Comprehensive device and app snapshot. Single call returns everything an agent needs to understand the runtime environment.

**Parameters:** none

**Response:**
```json
{
  "platform": "iOS",
  "frameworkType": "uikit",

  "bundleId": "com.example.app",
  "appName": "MyApp",
  "displayName": "My App",
  "version": "2.1.0",
  "build": "42",
  "minOSVersion": "16.0",
  "executableName": "MyApp",

  "deviceModel": "iPhone",
  "deviceName": "iPhone 16 Pro",
  "systemName": "iPhone OS",
  "systemVersion": "18.2",
  "userInterfaceIdiom": "phone",
  "identifierForVendor": "...",
  "isSimulator": false,

  "osVersionString": "Version 18.2 (Build 22C150)",
  "osVersion": { "major": 18, "minor": 2, "patch": 0 },
  "processName": "MyApp",
  "processId": 12345,
  "hostName": "iPhone",
  "processorCount": 6,
  "activeProcessorCount": 6,
  "physicalMemoryMB": 8192,
  "isLowPowerMode": false,
  "thermalState": "nominal",

  "screen": {
    "width": 393,
    "height": 852,
    "scale": 3.0,
    "nativeWidth": 1179,
    "nativeHeight": 2556,
    "nativeScale": 3.0,
    "brightness": 0.5
  },

  "battery": { "level": 0.87, "state": "unplugged" },

  "locale": {
    "identifier": "en_US",
    "languageCode": "en",
    "regionCode": "US",
    "currencyCode": "USD",
    "usesMetricSystem": false
  },

  "timeZone": {
    "identifier": "America/New_York",
    "abbreviation": "EST",
    "secondsFromGMT": -18000
  },

  "disk": { "freeMB": 45000, "totalMB": 128000 },

  "declaredPermissions": [
    "NSCameraUsageDescription",
    "NSLocationWhenInUseUsageDescription"
  ],

  "infoPlist": {
    "CFBundleIdentifier": "com.example.app",
    "CFBundleShortVersionString": "2.1.0",
    "NSCameraUsageDescription": "Used to scan barcodes",
    "...": "all other Info.plist keys"
  }
}
```

Android response includes the same categories plus Android-specific fields: `deviceManufacturer`, `deviceBrand`, `deviceFingerprint`, `sdkInt`, `securityPatch`, `supportedAbis`, `manifestMetaData`, `versionCode`, `targetSdk`, `minSdk`, `firstInstallTime`, `lastUpdateTime`, `isDebuggable`, `isEmulator`, memory breakdown (`totalRamMB`, `availableRamMB`, `isLowMemory`), display (`densityDpi`, `xdpi`, `ydpi`), and `declaredPermissions` from the manifest.

Flutter response includes `operatingSystem`, `operatingSystemVersion`, `numberOfProcessors`, `localHostname`, Dart runtime memory (`currentRss`, `maxRss`), and `environment` (non-secret process env vars).

React Native response mirrors iOS or Android depending on the host platform.

---

## WebView — DOM Access

All WebView tools accept an optional `webview_id` parameter. If omitted, the first discovered WebView is used. Use `get_webviews` to list available WebViews and their IDs.

### `get_webviews`
List all web views in the current screen.

**Parameters:** none

**Response:**
```json
{
  "count": 1,
  "webviews": [
    {
      "id": "webdemo.webview",
      "url": "https://example.com/",
      "title": "Example Domain",
      "loading": false,
      "canGoBack": false,
      "canGoForward": false,
      "frame": "0,116,402,758"
    }
  ]
}
```

---

### `get_dom_tree`
Full or partial DOM tree.

**Parameters:**
- `webview_id` (string, optional)
- `root` (string, optional) — CSS selector for subtree root
- `max_depth` (integer, optional)
- `visible_only` (boolean, optional)

---

### `get_dom_interactive`
All interactive DOM elements with auto-generated CSS selectors.

**Parameters:** `webview_id` (optional)

---

### `query_dom`
CSS selector query — returns matching elements with attributes.

**Parameters:**
- `selector` (string, required)
- `webview_id` (optional)
- `limit` (integer, optional)

---

### `find_dom_text`
Find elements by text content.

**Parameters:**
- `text` (string, required)
- `tag` (string, optional) — restrict to element type
- `webview_id` (optional)

---

### `web_click`
Click a DOM element by CSS selector.

**Parameters:**
- `selector` (string, required)
- `webview_id` (optional)

---

### `web_type`
Type text into an input or textarea. React/Vue/Angular compatible via native setter dispatch.

**Parameters:**
- `text` (string, required)
- `selector` (string, optional)
- `clear` (boolean, optional) — clear before typing
- `webview_id` (optional)

---

### `web_select`
Select a dropdown option.

**Parameters:**
- `value` (string, required)
- `selector` (string, optional)
- `webview_id` (optional)

---

### `web_toggle`
Check or uncheck a checkbox or radio button.

**Parameters:**
- `checked` (boolean, required)
- `selector` (string, optional)
- `webview_id` (optional)

---

### `web_scroll_to`
Scroll to a DOM element.

**Parameters:**
- `selector` (string, required)
- `webview_id` (optional)

---

### `web_evaluate`
Execute arbitrary JavaScript in the WebView.

**Parameters:**
- `javascript` (string, required)
- `webview_id` (optional)

**Response:** `{ "result": "<serialised return value>" }`

---

### `web_navigate`
Navigate to a URL.

**Parameters:**
- `url` (string, required)
- `webview_id` (optional)

---

### `web_back`
Go back in WebView history.

**Parameters:** `webview_id` (optional)

---

### `web_forward`
Go forward in WebView history.

**Parameters:** `webview_id` (optional)

---

## WebView — Token-Efficient Queries

### `get_dom_summary`
Compact page overview: title, meta tags, headings (h1–h3), element counts, form structure.

**Parameters:** `webview_id` (optional)

---

### `get_dom_text`
Visible text content stripped of all markup, respecting block layout.

**Parameters:**
- `selector` (string, optional) — scope to subtree
- `webview_id` (optional)

---

### `get_dom_links`
All `<a href>` links with text, href, and bounding rect.

**Parameters:** `webview_id` (optional)

---

### `get_dom_forms`
All forms with fields, types, current values, options, and CSS selectors. Falls back to scanning loose inputs on pages without `<form>`.

**Parameters:** `webview_id` (optional)

---

### `get_dom_headings`
All h1–h6 headings with text, level, and bounding rect.

**Parameters:** `webview_id` (optional)

---

### `get_dom_images`
All `<img>` elements with src, alt, and dimensions.

**Parameters:** `webview_id` (optional)

---

### `get_dom_tables`
All tables with headers and row data.

**Parameters:** `webview_id` (optional)

---

## Batch Operations

### `batch`
Execute multiple tool calls in a single request. Actions run sequentially.

**Parameters:**
- `actions` (array, required) — each item: `{ "tool": "tool_name", "arguments": { ... }, "delay_ms": 500 }`
  - `delay_ms` — milliseconds to wait **before** this action (for animations, transitions, loading states)
- `stop_on_error` (boolean, optional) — default false

**Response:**
```json
{
  "results": [
    { "index": 0, "tool": "tap_element", "success": true, "result": { ... } },
    { "index": 1, "tool": "type_text",   "success": true, "result": { ... } }
  ]
}
```

**Example — log in and verify the orders screen:**
```json
{
  "tool": "batch",
  "arguments": {
    "actions": [
      { "tool": "type_text", "arguments": { "element_id": "login.email",    "text": "user@example.com" } },
      { "tool": "type_text", "arguments": { "element_id": "login.password", "text": "password" } },
      { "tool": "tap_element", "arguments": { "element_id": "login.submit" } },
      { "tool": "get_screen", "arguments": {}, "delay_ms": 800 }
    ]
  }
}
```

---

## macOS Desktop Tools

These tools are only available on macOS targets.

### `get_menu_bar`
Read the app's main menu bar hierarchy recursively.

**Parameters:** none

**Response:**
```json
{
  "menus": [
    {
      "title": "File",
      "items": [
        { "title": "New", "keyEquivalent": "n", "enabled": true },
        { "title": "Open...", "keyEquivalent": "o", "enabled": true }
      ]
    }
  ]
}
```

---

### `click_menu_item`
Invoke a menu item by its title path.

**Parameters:**
- `title_path` (string, required) -- menu item path, e.g. `"File > Save"`

**Response:** `{ "success": true }`

---

### `focus_window`
Bring a specific window to the front and make it the key window.

**Parameters:**
- `window_id` (string, required) -- window ID from `list_windows`

**Response:** `{ "success": true }`

---

## Element ID Conventions

| Platform | Mechanism |
|----------|-----------|
| iOS | `view.accessibilityIdentifier` |
| macOS | `view.accessibilityIdentifier()` |
| Android | `view.tag` (via `R.id.appreveal_id`) or resource entry name or `contentDescription` |
| Flutter | `ValueKey<String>` on the widget |
| React Native | `testID` prop (maps to `accessibilityIdentifier` on iOS, resource name on Android) |

Screen key and element ID naming:

| Thing | Pattern | Examples |
|-------|---------|----------|
| Screen key | `section.screen` | `auth.login`, `order.detail`, `settings.main` |
| Element ID | `screen.element` | `login.email`, `login.submit`, `orders.cell_0` |
