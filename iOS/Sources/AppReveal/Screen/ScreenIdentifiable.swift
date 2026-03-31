// Protocol for screens to provide stable identity

import Foundation

#if DEBUG

/// Conform your view controllers or SwiftUI screens to provide
/// stable, machine-readable screen identity.
///
/// Examples of screen keys: "auth.login", "orders.detail", "checkout.payment"
public protocol ScreenIdentifiable: AnyObject {
    /// Stable dot-separated key identifying this screen (e.g. "auth.login")
    var screenKey: String { get }

    /// Human-readable screen title
    var screenTitle: String { get }

    /// Additional metadata for debugging
    var debugMetadata: [String: Any] { get }
}

public extension ScreenIdentifiable {
    var debugMetadata: [String: Any] { [:] }
}

/// Information about the currently active screen.
public struct ScreenInfo: Codable {
    public let screenKey: String
    public let screenTitle: String
    public let frameworkType: String // "uikit", "swiftui", "appkit"
    public let controllerChain: [String]
    public let activeTab: String?
    public let navigationDepth: Int
    public let presentedModals: [String]
    public let confidence: Double
    /// How the screen was identified: "explicit", "derived"
    public let source: String
    /// Title extracted from navigation bar (iOS) or window title (macOS)
    public let appBarTitle: String?
}

#endif
