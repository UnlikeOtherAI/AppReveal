# AppReveal -- iOS

## Requirements

- iOS 16.0+
- Swift 5.9+
- Xcode 15+

## Installation

### Swift Package Manager

```swift
.package(url: "https://github.com/UnlikeOtherAI/AppReveal.git", from: "0.2.0")
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

### 2. Add screen identity (optional)

Screen identity is auto-derived from class names -- `LoginViewController` becomes key `"login"`, title `"Login"`. Override only when you want a custom key:

```swift
#if DEBUG
extension LoginViewController: ScreenIdentifiable {
    var screenKey: String { "auth.login" }
    var screenTitle: String { "Login" }
}
#endif
```

### 3. Add accessibility identifiers

```swift
emailField.accessibilityIdentifier = "login.email"
passwordField.accessibilityIdentifier = "login.password"
loginButton.accessibilityIdentifier = "login.submit"
```

### 4. Connect and use

```bash
# Discover the service
dns-sd -B _appreveal._tcp local.

# Initialize MCP session
curl -X POST http://localhost:<port>/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'

# Get current screen
curl -X POST http://localhost:<port>/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_screen","arguments":{}}}'
```

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
- Local network only (NWListener)
- Sensitive headers (Authorization, Cookie) redacted in network capture

## Platform details

- Transport: NWListener (Network.framework)
- Discovery: NWListener.Service (Bonjour/mDNS)
- View hierarchy: UIView tree walking
- Screenshots: UIGraphicsImageRenderer
- WebView: WKWebView + evaluateJavaScript

## Example app

See [`example/iOS/`](../example/iOS/) for a full example with 11 screens, 60+ elements, and all framework features.
