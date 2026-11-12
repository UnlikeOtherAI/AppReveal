# AppReveal Flutter Example

E-commerce shell demonstrating all AppReveal Flutter integration patterns.

## Screens

| Screen Key | Widget | Route |
|---|---|---|
| `auth.login` | `LoginScreen` | `/login` |
| `auth.signup` | `SignUpScreen` | `/signup` |
| `catalog.list` | `CatalogScreen` | `/main` (tab 0) |
| `catalog.detail` | `ProductDetailScreen` | `/catalog/detail` |
| `orders.list` | `OrdersListScreen` | `/orders` |
| `orders.detail` | `OrderDetailScreen` | `/orders/detail` |
| `cart.main` | `CartScreen` | `/main` (tab 2) |
| `profile.main` | `ProfileScreen` | `/main` (tab 3) |
| `profile.edit` | `EditProfileScreen` | `/profile/edit` |
| `settings.main` | `SettingsScreen` | `/settings` |
| `webview.demo` | `WebViewDemoScreen` | `/webview` |

## Integration patterns demonstrated

- `AppReveal.start()` before `runApp`
- `AppReveal.wrap(app)` for screenshot support
- `AppReveal.navigatorObserver` in `MaterialApp.navigatorObservers`
- All four provider registrations (`StateProviding`, `NavigationProviding`, `FeatureFlagProviding`, `NetworkObservable`)
- `ScreenIdentifiable` mixin on all screen states
- `ValueKey<String>` on all interactive elements (pattern: `screen.element`)
- `AppReveal.registerWebView` / `unregisterWebView` lifecycle

## Repeatable Windows MCP verification

The Windows runner supports the native Flutter tools. `webview_flutter` does
not provide a Windows backend: do not select the WebView example tab on Windows.
Run that tab on Android, iOS or macOS with a supported WebView backend instead.

From `Flutter/example`, using a configured Flutter SDK and Visual Studio C++ tools:

```powershell
flutter pub get
flutter analyze --fatal-infos
flutter run -d windows -t tool/verify_mcp.dart
```

The verification entry point launches the real example and makes authenticated
HTTP MCP calls for inventory, text edits, login, scrolling, product/cart state,
tabs, navigation, modal dismissal, diagnostics, batch error recovery, and PNG/JPEG
screenshots. It checks resulting state and exits nonzero on failure. Session
tokens stay in memory. To save its JSON report, add
`--dart-define=APPREVEAL_EVIDENCE_DIR=C:/path/to/evidence`.

From `Flutter/appreveal`, run the shared regressions and the browser-backed DOM
payload checks (the latter require Node, Playwright, and installed Chrome):

```powershell
flutter pub get
flutter analyze --fatal-infos
flutter test --concurrency=2
npm.cmd install --no-save --package-lock=false playwright
dart run tool/export_dom_checks.dart dom-checks.json
node tool/verify_dom.cjs dom-checks.json
```

The DOM checks execute the actual generated JavaScript in Chrome, including
successful mutations and disabled/missing-target failures. They do not verify
the Android or Apple WebView transport. Delete `dom-checks.json` after the run.
