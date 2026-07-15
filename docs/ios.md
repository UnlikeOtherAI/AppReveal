# AppReveal -- iOS

## Requirements

- iOS 16.0+
- Swift 5.9+
- Xcode 15+

## Installation

### Swift Package Manager

```swift
.package(url: "https://github.com/UnlikeOtherAI/AppReveal.git", from: "0.10.1")
```

## Quick start

### 1. Start the server

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

WKWebView support works automatically -- no additional integration needed.

When the listener is ready, AppReveal prints a loopback URL and an authenticated session URL. You can also read them from `AppReveal.url`, `AppReveal.sessionURL`, and `AppReveal.sessionToken`.

### SwiftUI tap support on iOS 26+

On iOS 26+ SwiftUI gesture recognisers require private UIKit APIs for synthetic tap delivery (`IOHIDDigitizerEvent` + `UIApplication._enqueueHIDEvent:`). AppReveal gates this code behind the `APPREVEAL_PRIVATE_API_TAPS` compile flag, which is set automatically for debug builds in `Package.swift`:

| Build configuration | Private API code | Notes |
|---|---|---|
| Debug | ✅ compiled in | SwiftUI taps work |
| Release | ❌ absent | No private symbols — safe for App Store review |

No setup needed. The flag is already wired up in AppReveal's `Package.swift`.

#### Opting out of private APIs entirely

If your team prefers zero private API usage even in debug builds, remove (or comment out) the `swiftSettings` entry from AppReveal's `Package.swift`:

```swift
// iOS/Package.swift — remove to disable private API taps in all builds:
// .define("APPREVEAL_PRIVATE_API_TAPS", .when(configuration: .debug))
```

Without the flag, `tap_point` still works for all UIKit views and SwiftUI views on iOS < 26. On iOS 26+ SwiftUI buttons will not respond to synthetic taps.

### 2. Register SwiftUI elements when you need stable IDs or direct activation

On iOS 26, SwiftUI can defer building its accessibility tree until an assistive technology is actually running. AppReveal first asks UIKit/SwiftUI for accessibility and automation elements. When those APIs still return an empty SwiftUI subtree, AppReveal falls back to Vision text recognition inside SwiftUI hosting views. This makes visible SwiftUI text appear in `get_elements` with `idSource: "ocr"` and lets `tap_text("Send")` tap the recognized text location.

For the most stable automation, apply `.appReveal("id")` to SwiftUI views that agents need to interact with. For buttons in `ScrollView`, `LazyVGrid`, or other gesture-heavy containers, pass the optional `activate:` closure so AppReveal can invoke the debug action directly instead of depending on coordinate synthesis.

```swift
// Works on iOS 16+ — no-op in release (compiled only under #if DEBUG)
Button(action: sendMessage) {
    Image(systemName: "arrow.up.circle.fill")
}
#if DEBUG
.appReveal("chat.send_button", label: "Send", activate: sendMessage)
#endif

Button("Submit") { submit() }
#if DEBUG
.appReveal("form.submit", activate: submit)
#endif
```

After this, `get_elements` returns the element with `idSource: "appReveal"` and `tap_element("chat.send_button")` or `tap_text("Send")` can find it. If an `activate:` closure is registered, AppReveal calls that closure directly; otherwise it falls back to the SwiftUI-aware coordinate path used by `tap_point`.

**Elements without `.appReveal()`:** UIKit views (`UIButton`, `UITextField`, `UISwitch`, etc.) and SwiftUI elements that surface through accessibility or automation APIs continue to work automatically. On iOS 26+ SwiftUI views that stay hidden from those APIs can still be tapped by visible text through OCR. `tap_element` also tries OCR text candidates derived from the requested identifier, so IDs such as `device.chip.mouser` can fall back to visible text like `mouser`. OCR cannot recover an arbitrary hidden `accessibilityIdentifier`; use `.appReveal("stable.id")` when exact ID inventory matters.

### 3. Add Bonjour keys to `Info.plist`

Loopback simulator testing works without Bonjour, but physical-device discovery and LAN clients need Local Network permission:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>AppReveal uses the local network for debug MCP connections.</string>
<key>NSBonjourServices</key>
<array>
    <string>_appreveal._tcp</string>
</array>
```

### 4. Add screen identity (optional)

Screen identity is auto-derived from class names -- `LoginViewController` becomes key `"login"`, title `"Login"`. Override only when you want a custom key:

```swift
#if DEBUG
extension LoginViewController: ScreenIdentifiable {
    var screenKey: String { "auth.login" }
    var screenTitle: String { "Login" }
}
#endif
```

### 5. Add accessibility identifiers

```swift
emailField.accessibilityIdentifier = "login.email"
passwordField.accessibilityIdentifier = "login.password"
loginButton.accessibilityIdentifier = "login.submit"
```

### 6. Connect and use

```bash
# Discover the service
dns-sd -B _appreveal._tcp local.

# Check listener health. This endpoint is intentionally unauthenticated.
curl http://localhost:<port>/health

# Copy the token from the AppReveal log or AppReveal.sessionToken.
TOKEN="<session-token>"

# Initialize MCP session
curl -X POST http://localhost:<port>/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'

# Get current screen
curl -X POST http://localhost:<port>/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_screen","arguments":{}}}'
```

For manual testing you can also paste the printed `AppReveal.sessionURL`, which carries the token as `appreveal_session_token`. For LAN clients, resolve the Bonjour service host/port and include the same token via `Authorization: Bearer <token>` or `X-AppReveal-Session`.

`GET /health` returns `bonjourDiagnostics` and `lan` objects. Use them when a device is reachable by loopback but not by LAN:

- `bonjour: "advertising"` means mDNS published successfully.
- `bonjour: "suppressed"` means AppReveal kept the HTTP listener running but did not advertise because no usable LAN interface/path was visible. Check `bonjourDiagnostics.suppressionReason`.
- `bonjour: "retrying"` or `"failed"` includes `lastError` and `lastErrorHint`; `-65555` is Bonjour `NoAuth`, usually Local Network permission or missing `NSBonjourServices`.
- If iOS asks for Local Network permission after `AppReveal.start()`, grant it and return to the app. AppReveal retries Bonjour when the app becomes active again, so you do not need to restart the debug build.
- `lan.interfaces` lists the process-visible IPv4/IPv6 interfaces and marks which ones are LAN candidates.

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

## Security

- All code behind `#if DEBUG` -- zero production footprint
- Generated per-session token required for MCP POST requests
- Health diagnostics available at `GET /health`
- Loopback CORS only; LAN clients should use native MCP clients or explicit headers
- Local Network permission and Bonjour keys required for physical-device discovery
- Bonjour publish failures retry automatically; advertising is suppressed when no LAN candidate is visible
- Sensitive headers (Authorization, Cookie) redacted in network capture

## Platform details

- Transport: NWListener (Network.framework)
- Discovery: NetService (Bonjour/mDNS) publishing `_appreveal._tcp` after listener readiness and LAN diagnostics
- View hierarchy: UIView tree walking
- Screenshots: UIGraphicsImageRenderer
- WebView: WKWebView + evaluateJavaScript; `tap_point` routes into DOM clicks when the point lands inside a WebView

## Example app

See [`example/iOS/`](../example/iOS/) for a full example with 11 screens, 60+ elements, and all framework features.
