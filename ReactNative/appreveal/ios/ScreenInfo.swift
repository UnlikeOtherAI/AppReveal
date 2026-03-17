// Screen identity model

import Foundation

/// Information about the currently active screen.
public struct ScreenInfo: Codable {
    public let screenKey: String
    public let screenTitle: String
    public let frameworkType: String // "uikit", "swiftui", "mixed"
    public let controllerChain: [String]
    public let activeTab: String?
    public let navigationDepth: Int
    public let presentedModals: [String]
    public let confidence: Double
}
