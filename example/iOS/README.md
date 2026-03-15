# AppReveal Example -- iOS

Example iOS app demonstrating all AppReveal framework features.

## Screens

| Screen Key | View Controller | Elements |
|---|---|---|
| `auth.login` | LoginViewController | email, password, submit, forgot_password, sign_up, error, loading |
| `auth.signup` | SignUpViewController | name, email, password, confirm_password, terms_toggle, submit, cancel |
| `orders.list` | OrdersListViewController | list_table, search, filter, refresh, cell_N |
| `orders.detail` | OrderDetailViewController | scroll, status, total, items, track, cancel, reorder, notes, rating_slider, rating_value |
| `catalog.list` | CatalogViewController | grid, search, cart, product_N, add_to_cart_N |
| `catalog.detail` | ProductDetailViewController | scroll, image, name, price, description, quantity_stepper, quantity_label, add_to_cart, favorite |
| `cart.main` | CartViewController | title, close, items_table, item_N, total, checkout, empty_message |
| `profile.main` | ProfileViewController | avatar, name, email, member_since, order_count, tab_selector, edit, logout |
| `profile.edit` | EditProfileViewController | name, bio, notifications_toggle, save, cancel |
| `settings.main` | SettingsViewController | table, dark_mode, push_enabled, delete_account, ... |

## Element types covered

- UIButton (login.submit, cart.checkout, etc.)
- UITextField (login.email, login.password, order_detail.notes)
- UITextView (edit_profile.bio)
- UISwitch (signup.terms_toggle, edit_profile.notifications_toggle)
- UISlider (order_detail.rating_slider)
- UIStepper (product_detail.quantity_stepper)
- UITableView (orders.list_table, settings.table)
- UICollectionView (catalog.grid)
- UIScrollView (order_detail.scroll, product_detail.scroll)
- UISegmentedControl (profile.tab_selector)
- UISearchBar (orders.search, catalog.search)
- UIImageView (login.logo, profile.avatar)

## Framework features exercised

- **ScreenIdentifiable** -- all 10 screens conform with screenKey, screenTitle, debugMetadata
- **Accessibility identifiers** -- 60+ elements with dot-prefixed IDs
- **StateProviding** -- ExampleStateContainer exposes login state, user info, cart count
- **NavigationProviding** -- ExampleRouter tracks route stack and modal stack
- **FeatureFlagProviding** -- ExampleFeatureFlags exposes 8 flags
- **NetworkObservable** -- ExampleNetworkClient captures all simulated API calls
- **Scrolling** -- scroll views in order detail and product detail
- **Modals** -- sign up, cart, edit profile presented as sheets
- **Tab bar** -- 4 tabs (orders, catalog, profile, settings)
- **Navigation** -- push/pop in orders and catalog
- **Deep links** -- ExampleRouter handles appreveal://orders/ORD-001 etc.

## Setup

### Option A: XcodeGen (recommended)

```bash
brew install xcodegen  # if not installed
cd example/iOS/AppRevealExample
xcodegen generate
open AppRevealExample.xcodeproj
```

### Option B: Manual Xcode project

1. Create a new iOS App project in Xcode
2. Add the local AppReveal package (point to `iOS/` folder)
3. Drag all source folders into the project
4. Set deployment target to iOS 16.0
5. Build and run on simulator
