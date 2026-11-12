package com.appreveal.screen

/**
 * Implement on Activities or Fragments to provide stable, machine-readable screen identity.
 *
 * Examples of screen keys: "auth.login", "orders.detail", "checkout.payment"
 */
interface ScreenIdentifiable {
    val screenKey: String
    val screenTitle: String
    val debugMetadata: Map<String, Any> get() = emptyMap()
}
