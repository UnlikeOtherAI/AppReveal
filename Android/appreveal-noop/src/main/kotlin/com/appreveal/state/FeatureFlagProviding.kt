package com.appreveal.state

/**
 * Implement on your feature flag system to expose flags to AppReveal.
 */
interface FeatureFlagProviding {
    fun allFlags(): Map<String, Any?>
}
