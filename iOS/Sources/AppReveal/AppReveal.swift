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

    public static var sessionToken: String? {
        shared.server?.sessionToken
    }

    public static var url: String? {
        shared.server?.url
    }

    public static var sessionURL: String? {
        shared.server?.sessionURL
    }

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
        #elseif os(macOS)
        MacOSScreenResolver.shared.register(screen)
        #endif
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
        if let server {
            let endpoint = server.sessionURL ?? server.url ?? "starting"
            print("[AppReveal] start ignored; already running at \(endpoint)")
            return
        }

        #if os(iOS)
        URLSessionCapture.shared.install()
        #endif
        registerBuiltInTools()
        registerWebViewTools()
        let server = MCPServer(port: port)
        self.server = server
        if !server.start() {
            self.server = nil
        }
    }
}

#endif
