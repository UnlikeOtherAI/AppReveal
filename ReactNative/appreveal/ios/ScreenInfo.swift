// Screen identity model

import Foundation

/// Information about the currently active screen.
public struct ScreenInfo: Codable {
    public let screenKey: String
    public let screenTitle: String
    public let frameworkType: String // "uikit", "swiftui"
    public let controllerChain: [String]
    public let activeTab: String?
    public let navigationDepth: Int
    public let presentedModals: [String]
    public let confidence: Double
    /// How the screen was identified: "explicit", "derived"
    public let source: String
    /// Title extracted from navigation bar
    public let appBarTitle: String?
}
