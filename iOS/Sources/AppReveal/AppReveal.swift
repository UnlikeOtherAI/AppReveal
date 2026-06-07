// AppReveal -- Debug-only in-app MCP framework for iOS and macOS
// Use only in DEBUG builds: #if DEBUG / AppReveal.start() / #endif

import Foundation

#if DEBUG

/// Main entry point for the AppReveal debug framework.
/// Call `AppReveal.start()` in your app's launch sequence within `#if DEBUG`.
@MainActor
public final class AppReveal {

    public static let shared = AppReveal()

    private var server: MCPServer?

    private init() {}

    /// Allow AppReveal to use private UIKit APIs for synthetic tap delivery on iOS 26+.
    ///
    /// When `true`, `tap_point` and `tap_element` on SwiftUI views inject an
    /// `IOHIDDigitizerEvent` via `UIApplication._enqueueHIDEvent:` so SwiftUI gesture
    /// recognisers fire correctly. This is the only reliable tap path on iOS 26+, but
    /// requires private Apple APIs. Opt-in because some teams prefer to avoid private
    /// API usage even in debug builds. Set to `true` before calling `AppReveal.start()`.
    ///
    /// Defaults to `false`.
    public static var privateAPITapsEnabled: Bool = false

    /// Start the AppReveal MCP server and Bonjour advertising.
    /// - Parameter port: Optional specific port. Uses a dynamic port if nil.
    public static func start(port: UInt16? = nil) {
        Task { @MainActor in
            shared.launch(port: port)
        }
    }

    /// Stop the server and remove Bonjour advertisement.
    public static func stop() {
        shared.server?.stop()
        shared.server = nil
    }

    // MARK: - Registration

    /// Register a screen identity provider for the current screen.
    public static func registerScreen(_ screen: ScreenIdentifiable) {
        #if os(iOS)
        ScreenResolver.shared.register(screen)
        #endif
        // macOS ScreenResolver will be added in Task 10
    }

    /// Register an app state provider.
    public static func registerStateProvider(_ provider: StateProviding) {
        StateBridge.shared.registerStateProvider(provider)
    }

    /// Register a navigation provider.
    public static func registerNavigationProvider(_ provider: NavigationProviding) {
        StateBridge.shared.registerNavigationProvider(provider)
    }

    /// Register a feature flag provider.
    public static func registerFeatureFlagProvider(_ provider: FeatureFlagProviding) {
        StateBridge.shared.registerFeatureFlagProvider(provider)
    }

    /// Register a network observable client.
    public static func registerNetworkObservable(_ observable: NetworkObservable) {
        NetworkObserverService.shared.register(observable)
    }

    // MARK: - Private

    private func launch(port: UInt16?) {
        #if os(iOS)
        URLSessionCapture.shared.install()
        #endif
        registerBuiltInTools()
        registerWebViewTools()
        let server = MCPServer(port: port)
        self.server = server
        server.start()
    }
}

#endif
