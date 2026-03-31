package com.appreveal.screen

/**
 * Information about the currently active screen.
 * Mirrors the iOS ScreenInfo struct exactly.
 */
data class ScreenInfo(
    val screenKey: String,
    val screenTitle: String,
    val frameworkType: String, // "android", "compose", "unknown"
    val activityChain: List<String>, // equivalent of iOS controllerChain
    val activeTab: String?,
    val navigationDepth: Int,
    val presentedModals: List<String>,
    val confidence: Double,
    val source: String, // "explicit", "derived"
    val appBarTitle: String?, // extracted from Toolbar/ActionBar
)
