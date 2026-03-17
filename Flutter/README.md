# AppReveal — Flutter

Debug-only MCP framework for Flutter. Gives LLM agents full native app control via the standard MCP protocol. Exposes the same 43 tools as the iOS and Android implementations.

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

Without it, AppReveal auto-derives the screen key from the route name (confidence 0.8).

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

All 43 tools are identical to iOS and Android:

### UI / Native (22)
`get_screen`, `get_elements`, `get_view_tree`, `screenshot`, `tap_element`, `tap_point`, `type_text`, `clear_text`, `scroll`, `scroll_to_element`, `select_tab`, `navigate_back`, `dismiss_modal`, `open_deeplink`, `get_state`, `get_navigation_stack`, `get_feature_flags`, `get_network_calls`, `get_logs`, `get_recent_errors`, `launch_context`, `batch`

### WebView / DOM (21)
`get_webviews`, `get_dom_tree`, `get_dom_interactive`, `query_dom`, `find_dom_text`, `web_click`, `web_type`, `web_select`, `web_toggle`, `web_scroll_to`, `web_evaluate`, `web_navigate`, `web_back`, `web_forward`, `get_dom_links`, `get_dom_text`, `get_dom_forms`, `get_dom_headings`, `get_dom_images`, `get_dom_tables`, `get_dom_summary`

## Flutter-specific notes

| Feature | Flutter approach |
|---|---|
| Element IDs | `ValueKey<String>` on widgets |
| Interaction | `GestureBinding` pointer injection |
| Screen identity | `ScreenIdentifiable` mixin on `State` |
| Route tracking | `AppRevealNavigatorObserver` |
| Screenshots | `AppReveal.wrap(app)` wraps root in `RepaintBoundary` |
| Text input | Direct `TextEditingController` update after focus |
| WebView JS | `WebViewController.runJavaScriptReturningResult` |
| Release guard | `kReleaseMode` check — zero code in release builds |

## Discovery

The server advertises via mDNS as `_appreveal._tcp.local` with TXT records:
- `bundleId` — app package name
- `version` — app version
- `transport` — `streamable-http`

Connect with any MCP client using `http://localhost:<port>`.
