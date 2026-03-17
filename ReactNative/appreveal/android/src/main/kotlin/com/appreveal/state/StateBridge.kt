package com.appreveal.state

/**
 * Bridges app state, navigation, and feature flags to AppReveal.
 * In React Native, all state is set directly from JS via the native module methods.
 * No protocol delegates — stored properties only.
 */
internal object StateBridge {

    // Navigation state — set by AppRevealModule.setNavigationStack()
    @Volatile var currentRoute: String = ""
    @Volatile var navigationStack: List<String> = emptyList()
    @Volatile var presentedModals: List<String> = emptyList()

    // Feature flags — set by AppRevealModule.setFeatureFlags()
    @Volatile var featureFlags: Map<String, Any> = emptyMap()

    // App state snapshot — set by AppRevealModule.setState() if ever needed
    // For now, returns an empty map (RN apps push state via captureNetworkCall etc.)
    @Volatile var stateSnapshot: Map<String, Any?> = emptyMap()

    fun getState(): Map<String, Any?> {
        return stateSnapshot
    }

    fun getNavigationStack(): Map<String, Any?> {
        return mapOf(
            "currentRoute" to currentRoute,
            "navigationStack" to navigationStack,
            "presentedModals" to presentedModals
        )
    }

    fun getFeatureFlags(): Map<String, Any?> {
        @Suppress("UNCHECKED_CAST")
        return featureFlags as Map<String, Any?>
    }
}
