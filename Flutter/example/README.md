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
