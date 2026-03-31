package com.appreveal.screen

/**
 * Information about the currently active screen.
 * Mirrors the iOS ScreenInfo struct exactly.
 */
data class ScreenInfo(
    val screenKey: String,
    val screenTitle: String,
    val frameworkType: String,         // "android", "compose", "react-native", "unknown"
    val activityChain: List<String>,   // equivalent of iOS controllerChain
    val activeTab: String?,
    val navigationDepth: Int,
    val presentedModals: List<String>,
    val confidence: Double,
    /** How the screen was identified: "explicit", "derived" */
    val source: String,
    /** Title extracted from Toolbar/ActionBar */
    val appBarTitle: String?
)
