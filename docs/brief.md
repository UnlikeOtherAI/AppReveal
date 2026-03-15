# AppReveal -- Build Brief

## Goal

Build a debug-only, in-app MCP framework for iOS that gives LLM agents Playwright-like control over native apps. Uses Bonjour discovery and Streamable HTTP transport. Centered on explicit screen identity, accessibility identifiers, and app-owned state/network instrumentation.

## Design decisions

- **Streamable HTTP** transport (MCP standard) -- not WebSocket or custom
- **Bonjour/mDNS** for zero-config LAN discovery
- **Explicit instrumentation** -- screen keys, accessibility IDs, protocol conformance
- **No private APIs** -- no SwiftUI internal tree inspection
- **Convention-based adoption** -- one-line startup, protocol conformance for depth
- **Read-first rollout** -- observation tools before mutation tools
- **Swift Package** -- distributed as a Swift package, iOS 16+

## Phased implementation plan

### Phase 1: Foundation + Read tools
> MCP server, discovery, screen identification, element listing, screenshots

- [ ] Set up Swift Package structure (`iOS/Package.swift`, source folders)
- [ ] Define `ScreenIdentifiable` protocol
- [ ] Define `ElementInfo` model and element type enum
- [ ] Define `AnyCodable` utility type
- [ ] Implement `MCPMessage` (JSON-RPC request/response models)
- [ ] Implement `MCPRouter` (tool registration and dispatch)
- [ ] Implement `MCPServer` (NWListener-based HTTP server)
- [ ] Implement `BonjourAdvertiser` (mDNS service advertising)
- [ ] Implement `ScreenResolver` (UIKit hierarchy walking + protocol-based identity)
- [ ] Implement `ElementInventory` (view hierarchy enumeration)
- [ ] Implement `ScreenshotCapture` (UIGraphicsImageRenderer capture)
- [ ] Register MCP tools: `get_screen`, `get_elements`, `screenshot`
- [ ] Implement `AppReveal.start()` public entry point
- [ ] Write unit tests for MCPMessage serialization
- [ ] Write unit tests for ElementInfo model
- [ ] Add `NSLocalNetworkUsageDescription` and `NSBonjourServices` to example Info.plist
- [ ] Test Bonjour discovery from macOS (dns-sd or NWBrowser)
- [ ] Test MCP connection with a generic MCP client

### Phase 2: Interaction tools
> Tap, type, scroll, navigate

- [ ] Implement `InteractionEngine.tap(elementId:)`
- [ ] Implement `InteractionEngine.tap(point:)`
- [ ] Implement `InteractionEngine.type(text:elementId:)`
- [ ] Implement `InteractionEngine.clear(elementId:)`
- [ ] Implement `InteractionEngine.scroll(direction:containerId:)`
- [ ] Implement `InteractionEngine.scrollTo(elementId:)`
- [ ] Implement `InteractionEngine.navigateBack()`
- [ ] Implement `InteractionEngine.dismissModal()`
- [ ] Register MCP tools: `tap_element`, `tap_point`, `type_text`, `clear_text`, `scroll`, `scroll_to_element`
- [ ] Write integration test: tap button by ID
- [ ] Write integration test: type into text field

### Phase 3: State + Navigation
> App state, route state, feature flags, deep links

- [ ] Define `StateProviding` protocol
- [ ] Define `NavigationProviding` protocol
- [ ] Define `FeatureFlagProviding` protocol
- [ ] Implement `StateBridge` (protocol aggregation + snapshot)
- [ ] Register MCP tools: `get_state`, `get_navigation_stack`, `get_feature_flags`
- [ ] Implement `open_deeplink` tool (UIApplication.open)
- [ ] Implement `launch_context` tool (bundle info, environment)
- [ ] Implement `reset_app_state` tool (registered cleanup handlers)
- [ ] Write unit tests for StateBridge snapshot serialization

### Phase 4: Network observation
> Traffic capture, request/response details, metrics

- [ ] Define `NetworkObservable` protocol
- [ ] Define `CapturedRequest` / `CapturedResponse` models
- [ ] Implement `NetworkObserver` (ring buffer, URLSessionTaskMetrics integration)
- [ ] Register MCP tools: `get_network_calls`, `get_network_call_detail`
- [ ] Add request/response body capture with size limits
- [ ] Add sensitive header redaction (Authorization, Cookie, etc.)
- [ ] Write unit tests for ring buffer and redaction

### Phase 5: Network mocking
> Response injection, latency/timeout/offline simulation

- [ ] Implement `NetworkMocker` (URLProtocol subclass)
- [ ] Implement URL pattern matching for mock rules
- [ ] Register MCP tools: `mock_network_response`, `simulate_latency`, `simulate_timeout`, `disable_network`
- [ ] Add mock rule management (add, remove, list active mocks)
- [ ] Write unit tests for URL pattern matching
- [ ] Write integration test: mock a GET request and verify response

### Phase 6: Diagnostics
> Logs, errors, metrics

- [ ] Implement `DiagnosticsBridge` (OSLogStore queries)
- [ ] Add recent error capture (registered error handlers)
- [ ] Add MetricKit payload summary (if available)
- [ ] Register MCP tools: `get_logs`, `get_recent_errors`, `get_metrics_summary`
- [ ] Write unit tests for log query filtering

### Phase 7: Debug Overlay
> In-app console for testing without external client

- [ ] Implement `DebugOverlay` SwiftUI view
- [ ] Show server status (port, Bonjour name, connected clients)
- [ ] Show recent tool calls with timing
- [ ] Show recent network calls summary
- [ ] Show current screen identity
- [ ] Add manual tool execution input
- [ ] Add floating toggle button to show/hide overlay

### Phase 8: Polish + Documentation
> Example app, client library, documentation

- [ ] Create example iOS app demonstrating all protocols
- [ ] Create `AppRevealClient` companion module (NWBrowser + MCP client)
- [ ] Write integration tests with example app
- [ ] Write README quick start guide
- [ ] Write protocol conformance guide
- [ ] Write naming convention guide for screen keys and element IDs

## App team conventions

| Convention | Example | Why |
|---|---|---|
| Screen keys | `auth.login`, `orders.detail` | Stable screen identity for agents |
| Element IDs | `login.email`, `checkout.pay_now` | Machine-addressable controls |
| Centralized networking | Single `URLSession`-based client | Full traffic observability + mocking |
| Route exposure | Conform router to `NavigationProviding` | Agent can read navigation state |
| Debug-only | `#if DEBUG` around all AppReveal code | Zero production footprint |

## v2 tools (future)

- `set_state` -- controlled state mutation
- `trigger_viewmodel_action` -- invoke view model methods
- `simulate_push_payload` -- inject push notification
- `background_app` / `foreground_app` -- lifecycle control
- `record_session_trace` -- record interaction sequence
- `get_storage_snapshot` -- UserDefaults, Keychain summary
- `clear_session` -- logout/reset
- `get_accessibility_snapshot` -- full accessibility tree dump
