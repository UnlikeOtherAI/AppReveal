package com.appreveal.state

import com.appreveal.shared.MainThreadExecutor
import java.lang.ref.WeakReference

/**
 * Bridges app state, navigation, and feature flags to AppReveal.
 * Uses WeakReference to avoid memory leaks.
 */
internal object StateBridge {
    private var stateProviderRef: WeakReference<StateProviding>? = null
    private var navigationProviderRef: WeakReference<NavigationProviding>? = null
    private var featureFlagProviderRef: WeakReference<FeatureFlagProviding>? = null

    fun registerStateProvider(provider: StateProviding) {
        stateProviderRef = WeakReference(provider)
    }

    fun registerNavigationProvider(provider: NavigationProviding) {
        navigationProviderRef = WeakReference(provider)
    }

    fun registerFeatureFlagProvider(provider: FeatureFlagProviding) {
        featureFlagProviderRef = WeakReference(provider)
    }

    fun getState(): Map<String, Any?> = MainThreadExecutor.runBlocking { stateProviderRef?.get()?.snapshot() ?: emptyMap() }

    fun getNavigationStack(): Map<String, Any?> =
        MainThreadExecutor.runBlocking {
            val nav = navigationProviderRef?.get() ?: return@runBlocking emptyMap()
            mapOf(
                "currentRoute" to nav.currentRoute,
                "navigationStack" to nav.navigationStack,
                "presentedModals" to nav.presentedModals,
            )
        }

    fun getFeatureFlags(): Map<String, Any?> = MainThreadExecutor.runBlocking { featureFlagProviderRef?.get()?.allFlags() ?: emptyMap() }
}
