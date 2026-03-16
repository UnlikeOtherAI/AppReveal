package com.appreveal.example.services

import com.appreveal.state.FeatureFlagProviding

object ExampleFeatureFlags : FeatureFlagProviding {

    private val flags: Map<String, Any> = mapOf(
        "new_checkout_flow" to true,
        "dark_mode_v2" to false,
        "catalog_grid_layout" to true,
        "order_tracking_map" to false,
        "push_promo_enabled" to true,
        "max_cart_items" to 50,
        "api_version" to "v2",
        "ab_test_group" to "B"
    )

    fun isEnabled(flag: String): Boolean = flags[flag] as? Boolean ?: false

    override fun allFlags(): Map<String, Any?> = flags.toMap()
}
