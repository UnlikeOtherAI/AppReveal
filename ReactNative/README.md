# AppReveal — React Native

Debug-only in-app MCP server for React Native. Lets LLM agents discover, inspect, and control native apps over the local network via standard MCP protocol — like Playwright for native, with direct access to app state, navigation, network traffic, and native UI elements.

## How it works

```
Your App (debug build)                    External Agent
 +-- AppReveal (react-native-appreveal)   +-- mDNS browse for _appreveal._tcp
      +-- MCP Server (Streamable HTTP) <--+-- MCP client (curl, SDK, Claude, etc.)
      +-- mDNS advertisement              +-- LLM orchestration
      +-- Screen/element/state bridges
      +-- WebView DOM bridge
```

1. App calls `AppReveal.start()` in a debug build
2. Framework starts an HTTP server on a dynamic port
3. mDNS advertises the service as `_appreveal._tcp` on the LAN
4. Agent discovers the service, connects, and calls MCP tools

All 43 MCP tools are identical across iOS, Android, Flutter, and React Native.

## Installation

```bash
npm install react-native-appreveal
# or
yarn add react-native-appreveal
```

### iOS setup

```bash
cd ios && pod install
```

Add to `Info.plist`:
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>AppReveal uses the local network to expose a debug MCP server for AI-assisted testing.</string>
<key>NSBonjourServices</key>
<array>
  <string>_appreveal._tcp</string>
</array>
```

### Android setup

Add to `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
```

## Basic usage

```typescript
import { AppReveal, AppRevealFetchInterceptor } from 'react-native-appreveal';

// In your root component
useEffect(() => {
  if (__DEV__) {
    AppReveal.start();              // starts MCP server + mDNS
    AppRevealFetchInterceptor.install(); // intercepts fetch for network capture
  }
}, []);
```

### useAppRevealScreen hook

Call at the top of any screen component to register the current screen:

```typescript
import { useAppRevealScreen } from 'react-native-appreveal';

function OrdersScreen() {
  useAppRevealScreen('orders.list', 'Orders');
  // ...
}
```

### React Navigation integration

```tsx
import { AppReveal, createNavigationListener } from 'react-native-appreveal';
import { NavigationContainer } from '@react-navigation/native';

function App() {
  const navListener = createNavigationListener();

  return (
    <NavigationContainer
      ref={navListener.ref}
      onStateChange={navListener.onStateChange}>
      {/* ... */}
    </NavigationContainer>
  );
}
```

The navigation listener automatically calls `AppReveal.setScreen()` and `AppReveal.setNavigationStack()` on every route change.

### Fetch interceptor

Install once at startup — safe to call multiple times, only patches once:

```typescript
if (__DEV__) {
  AppRevealFetchInterceptor.install();
}
```

All `fetch()` calls are then captured and exposed via the `get_network_calls` MCP tool.

### Manual network capture

If your app uses a custom HTTP client:

```typescript
AppReveal.captureNetworkCall({
  id: uuid(),
  method: 'POST',
  url: 'https://api.example.com/login',
  statusCode: 200,
  requestTimestamp: Date.now(),
  responseTimestamp: Date.now() + 412,
});
```

### Feature flags

```typescript
AppReveal.setFeatureFlags({
  new_checkout: true,
  dark_mode_beta: false,
  loyalty_points: true,
});
```

### Error capture

```typescript
AppReveal.captureError('NetworkError', 'Connection timed out', stack);
```

## API reference

```typescript
class AppReveal {
  static start(port?: number): void;
  static stop(): void;
  static setScreen(key: string, title: string): void;
  static setNavigationStack(routes: string[], current: string, modals?: string[]): void;
  static setFeatureFlags(flags: Record<string, unknown>): void;
  static captureNetworkCall(call: CapturedRequest): void;
  static captureError(domain: string, message: string, stackTrace?: string): void;
  static createNavigationListener(): { ref: RefObject<any>; onStateChange: (state) => void };
}

function useAppRevealScreen(screenKey: string, screenTitle: string): void;

class AppRevealFetchInterceptor {
  static install(): void;
}
```

All methods are no-ops when `__DEV__` is false — no production impact.

## MCP tools (43 total)

### UI and navigation

| Tool | Description |
|------|-------------|
| `get_screen` | Current screen identity, controller chain, confidence score |
| `get_elements` | All visible interactive elements with id, type, frame, actions |
| `get_view_tree` | Full view hierarchy with class, frame, properties, accessibility info |
| `tap_element` | Tap by element identifier (buttons, cells, controls) |
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
| `get_logs` | Recent app logs |
| `get_recent_errors` | Recent captured errors |
| `launch_context` | App ID, version, device model, OS version |

### WebView — DOM access

| Tool | Description |
|------|-------------|
| `get_webviews` | List all web views with URL, title, loading state |
| `get_dom_tree` | Full or partial DOM tree |
| `get_dom_interactive` | All inputs, buttons, links, selects with selectors |
| `query_dom` | CSS selector query |
| `find_dom_text` | Find elements by text content |
| `web_click` | Click a DOM element by CSS selector |
| `web_type` | Type into input/textarea |
| `web_select` | Select a dropdown option |
| `web_toggle` | Check/uncheck a checkbox or radio |
| `web_scroll_to` | Scroll to a DOM element |
| `web_evaluate` | Run arbitrary JavaScript |
| `web_navigate` | Navigate to a URL |
| `web_back` | Go back in web view history |
| `web_forward` | Go forward in web view history |

### WebView — token-efficient queries

| Tool | Description |
|------|-------------|
| `get_dom_summary` | Page overview: title, meta, headings, element counts |
| `get_dom_text` | Visible text content stripped of markup |
| `get_dom_links` | All links — text and href |
| `get_dom_forms` | All forms with fields, types, values, options |
| `get_dom_headings` | All h1–h6 for page structure |
| `get_dom_images` | All images with src, alt, dimensions |
| `get_dom_tables` | All tables with headers and row data |

### Batch operations

| Tool | Description |
|------|-------------|
| `batch` | Execute multiple tools in one call. Supports `delay_ms` per action for animations/transitions and `stop_on_error`. |

## testID conventions

Element `testID` props map to `accessibilityIdentifier` on iOS and content description on Android.

| Thing | Pattern | Examples |
|-------|---------|----------|
| Screen keys | `section.screen` | `auth.login`, `orders.list`, `settings` |
| Element IDs | `screen.element` | `login.email`, `orders.cell_0`, `catalog.add_to_cart_2` |

### Standard element IDs in the example app

| Screen | testIDs |
|--------|---------|
| Login | `login.email`, `login.password`, `login.submit`, `login.forgot_password`, `login.sign_up` |
| Orders | `orders.list_table`, `orders.search`, `orders.cell_0` – `orders.cell_4` |
| Catalog | `catalog.grid`, `catalog.product_0` – `catalog.product_5`, `catalog.add_to_cart_0` – `catalog.add_to_cart_5` |
| Profile | `profile.avatar`, `profile.name`, `profile.email`, `profile.edit`, `profile.logout` |
| Edit Profile | `edit_profile.name`, `edit_profile.bio`, `edit_profile.notifications_toggle`, `edit_profile.save`, `edit_profile.cancel` |
| Settings | `settings.notifications`, `settings.darkMode`, `settings.language`, `settings.version` |
| Web View | `webdemo.webview` |

## Example app

The `example/` directory contains a full React Native app demonstrating all framework features:

- 8 screens with `testID` on all interactive elements
- React Navigation v7 with bottom tabs and nested stacks
- AppRevealFetchInterceptor capturing all simulated API calls
- Feature flags, state, and navigation stack reporting
- WebView with `react-native-webview`

### Run

```bash
cd example
npm install
cd ios && pod install && cd ..
npx react-native run-ios
# or
npx react-native run-android
```

## Security

All AppReveal code is guarded by `__DEV__` — zero production impact. Local network only. Sensitive headers (Authorization, Cookie) are redacted in network capture.

## License

MIT
