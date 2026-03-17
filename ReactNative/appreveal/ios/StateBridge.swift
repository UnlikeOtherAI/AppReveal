// Stores app state, navigation, and feature flags set by JS via the native module.
// Replaces the protocol-based StateBridge from the pure iOS implementation.

import Foundation

@MainActor
final class StateBridge {

    static let shared = StateBridge()

    // MARK: - Navigation (set by JS)
    var navigationStack: [String] = []
    var currentRoute: String = ""
    var presentedModals: [String] = []

    // MARK: - Feature flags (set by JS)
    var featureFlags: [String: AnyCodable] = [:]

    private init() {}

    // MARK: - Queries

    /// Returns empty dict — no StateProviding protocol in the RN module.
    /// JS manages its own state; use React DevTools or custom tooling for state inspection.
    func getState() -> [String: AnyCodable] {
        return [:]
    }

    func getNavigationStack() -> [String: AnyCodable] {
        return [
            "currentRoute": AnyCodable(currentRoute),
            "navigationStack": AnyCodable(navigationStack),
            "presentedModals": AnyCodable(presentedModals)
        ]
    }

    func getFeatureFlags() -> [String: AnyCodable] {
        return featureFlags
    }
}
