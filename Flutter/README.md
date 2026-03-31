# AppReveal — Flutter

Debug-only MCP framework for Flutter. Gives LLM agents full native app control via the standard MCP protocol. Exposes the same tool surface as the iOS and Android implementations.

## Installation

In your `pubspec.yaml`:

```yaml
dependencies:
  appreveal:
    git:
      url: https://github.com/your-org/appreveal
      path: Flutter/appreveal
```

## Setup

```dart
// main.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  AppReveal.start(); // no-ops in release builds

  // Optional providers
  AppReveal.registerStateProvider(MyStateContainer());
  AppReveal.registerNavigationProvider(MyRouter());
  AppReveal.registerFeatureFlagProvider(MyFlags());
  AppReveal.registerNetworkObservable(MyHttpClient());

  runApp(AppReveal.wrap(const MyApp())); // wrap enables screenshots
}
```

```dart
// In MaterialApp — enables automatic screen tracking
MaterialApp(
  navigatorObservers: [AppReveal.navigatorObserver],
  ...
)
```

## Element IDs

Use `ValueKey<String>` to give elements stable identifiers. Follow the screen-prefixed convention:

```dart
TextField(key: const ValueKey('login.email'), ...)
ElevatedButton(key: const ValueKey('login.submit'), ...)
ListView(key: const ValueKey('orders.list'), ...)
```

When no `ValueKey<String>` is present, AppReveal auto-derives a usable ID from visible text, semantics labels, or tooltips. Each element in `get_elements` includes an `idSource` field indicating how the ID was obtained:

| `idSource` | Meaning |
|---|---|
| `explicit` | `ValueKey<String>` set by the developer — stable across builds |
| `text` | Derived from the widget's visible text (e.g. `"Product Management"` → `product_management`) |
| `semantics` | Derived from a Semantics label |
| `tooltip` | Derived from a tooltip (IconButton, FAB) |
| `derived` | Hash-based fallback — least stable |

### Supported widget types for auto-discovery

`ElevatedButton`, `TextButton`, `OutlinedButton`, `FilledButton`, `IconButton`, `FloatingActionButton`, `ListTile`, `SwitchListTile`, `CheckboxListTile`, `ExpansionTile`, `GestureDetector`, `InkWell`, `PopupMenuButton`, `TextField`, `TextFormField`, `Checkbox`, `Switch`, `Radio`, `DropdownButton`, `DropdownButtonFormField`, `ListView`, `GridView`, `SingleChildScrollView`.

## Text-based targeting

The `tap_text` tool lets agents tap any visible text on screen without requiring a `ValueKey`. It finds the text and taps its nearest tappable ancestor widget.

```
tap_text("Product Management")          # exact match
tap_text("Product", match_mode: "contains")  # partial match
tap_text("Settings", occurrence: 1)      # second match when ambiguous
```

`tap_element` also supports text-based fallback resolution. If the given ID is not a `ValueKey`, it tries (in order):

1. Exact `ValueKey<String>` match
2. Exact Semantics label match
3. Derived ID match (normalized text on interactive widget)
4. Exact visible text → nearest tappable ancestor
5. Normalized visible text → nearest tappable ancestor

## Screen identity

Implement `ScreenIdentifiable` on screen states for reliable `get_screen` results:

```dart
class _LoginScreenState extends State<LoginScreen> with ScreenIdentifiable {
  @override
  String get screenKey => 'auth.login';

  @override
  String get screenTitle => 'Login';

  @override
  void initState() {
    super.initState();
    AppReveal.registerScreen(this);
  }
}
```

Without it, AppReveal resolves screen identity through a fallback chain:

| Priority | Source | Confidence | `source` field |
|---|---|---|---|
| 1 | `ScreenIdentifiable` mixin | 1.0 | `explicit` |
| 2 | Named route (e.g. `/settings`) | 0.8 | `route` |
| 3 | AppBar title text | 0.6 | `appbar` |
| 4 | Best-effort inference | 0.3 | `inferred` |

The response includes `source` and optional `appBarTitle` fields so agents know how reliable the identity is.

## WebView support

```dart
final controller = WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..loadRequest(Uri.parse('https://example.com'));

// Register with AppReveal
AppReveal.registerWebView('main', controller);

// Unregister when the widget is disposed
AppReveal.unregisterWebView('main');
```

All 21 WebView tools (`get_dom_tree`, `web_click`, `web_type`, etc.) then work against registered controllers using `webview_id: "main"`.

## Providers

All providers are optional. AppReveal degrades gracefully without them.

```dart
// App state snapshot for get_state
class MyState implements StateProviding {
  @override
  Map<String, dynamic> snapshot() => {
    'isLoggedIn': true,
    'userId': 'usr_123',
  };
}

// Navigation state for get_navigation_stack
class MyRouter implements NavigationProviding {
  @override String get currentRoute => '/home';
  @override List<String> get navigationStack => ['/home'];
  @override List<String> get presentedModals => [];
}

// Feature flags for get_feature_flags
class MyFlags implements FeatureFlagProviding {
  @override
  Map<String, dynamic> allFlags() => {'newCheckout': true};
}

// Network traffic for get_network_calls
// Call didCapture from your HTTP client interceptor
class MyHttpClient implements NetworkObservable { ... }
```

## Tools

### UI / Native (23)
`get_screen`, `get_elements`, `get_view_tree`, `screenshot`, `tap_element`, `tap_text`, `tap_point`, `type_text`, `clear_text`, `scroll`, `scroll_to_element`, `select_tab`, `navigate_back`, `dismiss_modal`, `open_deeplink`, `get_state`, `get_navigation_stack`, `get_feature_flags`, `get_network_calls`, `get_logs`, `get_recent_errors`, `launch_context`, `batch`

### WebView / DOM (21)
`get_webviews`, `get_dom_tree`, `get_dom_interactive`, `query_dom`, `find_dom_text`, `web_click`, `web_type`, `web_select`, `web_toggle`, `web_scroll_to`, `web_evaluate`, `web_navigate`, `web_back`, `web_forward`, `get_dom_links`, `get_dom_text`, `get_dom_forms`, `get_dom_headings`, `get_dom_images`, `get_dom_tables`, `get_dom_summary`

## Flutter-specific notes

| Feature | Flutter approach |
|---|---|
| Element IDs | `ValueKey<String>` on widgets; auto-derived from text/semantics when absent |
| Interaction | `GestureBinding` pointer injection |
| Screen identity | `ScreenIdentifiable` mixin on `State`; fallback to route name and AppBar title |
| Route tracking | `AppRevealNavigatorObserver` |
| Screenshots | `AppReveal.wrap(app)` wraps root in `RepaintBoundary` |
| Text input | Direct `TextEditingController` update after focus |
| Text targeting | `tap_text` finds visible text and taps its nearest tappable ancestor |
| WebView JS | `WebViewController.runJavaScriptReturningResult` |
| Release guard | `kReleaseMode` check — zero code in release builds |

## Discovery

The server advertises via mDNS as `_appreveal._tcp.local` with TXT records:
- `bundleId` — app package name
- `version` — app version
- `transport` — `streamable-http`

Connect with any MCP client using `http://localhost:<port>`.
