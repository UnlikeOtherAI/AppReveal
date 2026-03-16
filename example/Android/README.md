# AppReveal Example -- Android

Example Android app demonstrating all AppReveal framework features.

## Screens

| Screen Key | Fragment/Activity | Elements |
|---|---|---|
| `auth.login` | LoginActivity | email, password, submit, forgot_password, sign_up, error, loading |
| `auth.signup` | SignUpFragment | name, email, password, confirm_password, terms_toggle, submit, cancel |
| `orders.list` | OrdersListFragment | list_table, search, refresh, cell_N |
| `orders.detail` | OrderDetailFragment | scroll, status, total, items, track, cancel, reorder, notes, rating_slider, rating_value |
| `catalog.list` | CatalogFragment | grid, search, cart, product_N, add_to_cart_N |
| `catalog.detail` | ProductDetailFragment | scroll, image, name, price, description, quantity_stepper, quantity_label, add_to_cart, favorite |
| `cart.main` | CartFragment | title, close, items_table, total, checkout, empty_message |
| `profile.main` | ProfileFragment | avatar, name, email, member_since, order_count, tab_selector, edit, logout |
| `profile.edit` | EditProfileFragment | name, bio, notifications_toggle, save, cancel |
| `settings.main` | SettingsFragment | dark_mode, push_enabled, delete_account |
| `webview.demo` | WebViewDemoFragment | webview with interactive HTML page |

## Element types covered

- Button / MaterialButton (login.submit, cart.checkout, etc.)
- EditText (login.email, login.password, order_detail.notes)
- EditText multiline (edit_profile.bio)
- Switch / SwitchMaterial (signup.terms_toggle, edit_profile.notifications_toggle)
- SeekBar (order_detail.rating_slider)
- +/- Buttons as stepper (product_detail.quantity_stepper)
- RecyclerView (orders.list_table, catalog.grid)
- ScrollView / NestedScrollView (order_detail.scroll, product_detail.scroll)
- TabLayout (profile.tab_selector)
- SearchView (orders.search, catalog.search)
- ImageView (login.logo, profile.avatar)
- BottomNavigationView (5 tabs)

## Framework features exercised

- **ScreenIdentifiable** -- LoginActivity implements it, fragments auto-derived
- **Element tags** -- 60+ elements with `android:tag` identifiers
- **StateProviding** -- ExampleStateContainer exposes login state, user info, cart count
- **NavigationProviding** -- ExampleRouter tracks route stack and modal stack
- **FeatureFlagProviding** -- ExampleFeatureFlags exposes 8 flags
- **NetworkObservable** -- ExampleNetworkClient captures all simulated API calls
- **Scrolling** -- ScrollViews in order detail and product detail
- **Modals** -- LoginActivity as fullscreen modal, CartFragment as dialog
- **Bottom navigation** -- 5 tabs (Orders, Catalog, Profile, Settings, Web)
- **Navigation** -- Fragment navigation with back stack
- **Deep links** -- appreveal:// URL scheme handled

## Setup

```bash
cd example/Android
./gradlew :app:installDebug
adb shell am start -n com.appreveal.example/.MainActivity
```

## Connecting

```bash
# Check logcat for the port
adb logcat -s AppReveal

# Forward port (emulator)
adb forward tcp:56209 tcp:56209

# Test MCP
curl -X POST http://localhost:56209/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
```
