// Navigation and feature flag provider protocols

import Foundation

#if DEBUG

/// Conform your router/coordinator to expose navigation state.
public protocol NavigationProviding: AnyObject {
    var currentRoute: String { get }
    var navigationStack: [String] { get }
    var presentedModals: [String] { get }
}

/// Conform your feature flag system to expose flags.
public protocol FeatureFlagProviding: AnyObject {
    func allFlags() -> [String: AnyCodable]
}

#endif
