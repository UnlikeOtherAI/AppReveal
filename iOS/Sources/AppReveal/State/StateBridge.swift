// Bridges app state, navigation, and feature flags to AppReveal

import Foundation

#if DEBUG

/// Conform your app state container to expose state snapshots.
public protocol StateProviding: AnyObject {
    func snapshot() -> [String: AnyCodable]
}

@MainActor
final class StateBridge {

    static let shared = StateBridge()

    private weak var stateProvider: StateProviding?
    private weak var navigationProvider: NavigationProviding?
    private weak var featureFlagProvider: FeatureFlagProviding?
    private var resetHandlers: [() -> Void] = []

    private init() {}

    func registerStateProvider(_ provider: StateProviding) {
        stateProvider = provider
    }

    func registerNavigationProvider(_ provider: NavigationProviding) {
        navigationProvider = provider
    }

    func registerFeatureFlagProvider(_ provider: FeatureFlagProviding) {
        featureFlagProvider = provider
    }

    /// Register a handler called when `reset_app_state` is invoked.
    func registerResetHandler(_ handler: @escaping () -> Void) {
        resetHandlers.append(handler)
    }

    // MARK: - Queries

    func getState() -> [String: AnyCodable] {
        stateProvider?.snapshot() ?? [:]
    }

    func getNavigationStack() -> [String: AnyCodable] {
        guard let nav = navigationProvider else { return [:] }
        return [
            "currentRoute": AnyCodable(nav.currentRoute),
            "navigationStack": AnyCodable(nav.navigationStack),
            "presentedModals": AnyCodable(nav.presentedModals)
        ]
    }

    func getFeatureFlags() -> [String: AnyCodable] {
        featureFlagProvider?.allFlags() ?? [:]
    }

    func resetState() {
        for handler in resetHandlers {
            handler()
        }
    }
}

#endif
