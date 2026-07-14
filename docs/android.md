# AppReveal -- Android

## Requirements

- Android API 26+ (Android 8.0)
- Kotlin 1.9+
- Java 17

## Installation

### Gradle

Add the library as a `debugImplementation` dependency so it is excluded from release builds entirely:

```kotlin
// settings.gradle.kts -- include the library
includeBuild("path/to/AppReveal/Android") {
    dependencySubstitution {
        substitute(module("com.appreveal:appreveal")).using(project(":appreveal"))
        substitute(module("com.appreveal:appreveal-noop")).using(project(":appreveal-noop"))
    }
}

// app/build.gradle.kts
dependencies {
    debugImplementation("com.appreveal:appreveal")
    releaseImplementation("com.appreveal:appreveal-noop")  // release-safe empty artifact
}
```

The `appreveal-noop` module provides empty release methods so you don't need `BuildConfig.DEBUG` checks in your code, though they're recommended as a safety net.

## Quick start

### 1. Start the server

```kotlin
class MyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) {
            AppReveal.start(this)

            // Optional: register providers for deeper inspection
            AppReveal.registerStateProvider(myStateContainer)
            AppReveal.registerNavigationProvider(myRouter)
            AppReveal.registerFeatureFlagProvider(myFeatureFlags)
            AppReveal.registerNetworkObservable(myNetworkClient)
        }
    }
}
```

WebView support works automatically -- no additional integration needed.

When the listener is ready, AppReveal logs a loopback URL, an authenticated session URL, and the session token. You can also read them from `AppReveal.url`, `AppReveal.sessionUrl`, and `AppReveal.sessionToken`.

### 2. Add screen identity (optional)

Screen identity is auto-derived from class names -- `LoginFragment` becomes key `"login"`, `OrderDetailActivity` becomes `"order.detail"`. Override only when you want a custom key:

```kotlin
class LoginFragment : Fragment(), ScreenIdentifiable {
    override val screenKey = "auth.login"
    override val screenTitle = "Login"
}
```

### 3. Add element identifiers

Use `android:tag` in layouts for element identification (the Android equivalent of iOS `accessibilityIdentifier`):

```xml
<EditText
    android:id="@+id/emailField"
    android:tag="login.email" />

<EditText
    android:id="@+id/passwordField"
    android:tag="login.password" />

<Button
    android:id="@+id/loginButton"
    android:tag="login.submit" />
```

Or set programmatically:

```kotlin
emailField.tag = "login.email"
```

Element IDs are resolved in this order:
1. Custom AppReveal tag: `view.getTag(R.id.appreveal_id)`
2. Android resource ID name: `resources.getResourceEntryName(view.id)` (e.g., `"emailField"`)
3. View tag: `view.tag` as String
4. Content description: `view.contentDescription`

#### Jetpack Compose

Compose requires no additional AppReveal dependency or accessibility-service setup. AppReveal reads
the merged semantics tree exposed by `AndroidComposeView`, so `get_elements`, `get_view_tree`,
`tap_element`, `tap_text`, `type_text`, and `clear_text` work with Compose controls on API 26+.

Use `Modifier.testTag` for stable IDs:

```kotlin
OutlinedTextField(
    value = email,
    onValueChange = { email = it },
    modifier = Modifier.testTag("login.email"),
)

Button(
    onClick = ::submit,
    modifier = Modifier.testTag("login.submit"),
) {
    Text("Sign in")
}
```

AppReveal reads `TestTag` directly; `testTagsAsResourceId` is not required. When a tag is absent,
content descriptions and visible or editable text provide derived IDs. Compose actions are invoked
through their semantics callbacks, so the feature does not depend on TalkBack being enabled.

### 4. Connect and use

```bash
# The server port is logged to logcat:
# [AppReveal] MCP server listening on port 56209
# [AppReveal] Session URL: http://127.0.0.1:56209/?appreveal_session_token=<token>

# Check listener health. This endpoint is intentionally unauthenticated.
curl http://<device-ip>:<port>/health

TOKEN="<session-token>"

# Initialize MCP session
curl -X POST http://<device-ip>:<port>/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'

# Get current screen
curl -X POST http://<device-ip>:<port>/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_screen","arguments":{}}}'
```

For emulator, forward the port first:
```bash
adb forward tcp:56209 tcp:56209
curl -X POST http://localhost:56209/ ...
```

## Integration interfaces

```kotlin
/// Expose app state
interface StateProviding {
    fun snapshot(): Map<String, Any?>
}

/// Expose navigation state
interface NavigationProviding {
    val currentRoute: String
    val navigationStack: List<String>
    val presentedModals: List<String>
}

/// Expose feature flags
interface FeatureFlagProviding {
    fun allFlags(): Map<String, Any?>
}

/// Expose network traffic
interface NetworkObservable {
    val recentRequests: List<CapturedRequest>
    fun addObserver(observer: NetworkTrafficObserver)
}
```

## Security

- Library added as `debugImplementation` -- not included in release APK
- Generated per-session token required for MCP POST requests
- Health diagnostics available at `GET /health`
- Loopback CORS only
- NsdManager advertises `_appreveal._tcp` with `auth=session-token`
- Sensitive headers (Authorization, Cookie) redacted in network capture

## Platform details

- Transport: NanoHTTPD (embedded HTTP server)
- Discovery: NsdManager (Android Network Service Discovery)
- View hierarchy: ViewGroup walking plus dependency-free Jetpack Compose semantics traversal
- Screenshots: PixelCopy (API 26+) / View.drawToBitmap
- WebView: android.webkit.WebView + evaluateJavascript
- Thread model: NanoHTTPD worker threads + MainThreadExecutor for UI access

## Example app

See [`example/Android/`](../example/Android/) for a full example with View-based screens plus a
Compose semantics fixture, with all framework features integrated.
