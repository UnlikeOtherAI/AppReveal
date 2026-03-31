package com.appreveal.screen

/**
 * Information about the currently active screen.
 * Mirrors the iOS ScreenInfo struct exactly.
 */
data class ScreenInfo(
    val screenKey: String,
    val screenTitle: String,
    /** "android", "compose", "unknown" */
    val frameworkType: String,
    /** Equivalent of iOS controllerChain */
    val activityChain: List<String>,
    val activeTab: String?,
    val navigationDepth: Int,
    val presentedModals: List<String>,
    val confidence: Double,
    /** "explicit" or "derived" */
    val source: String,
    /** Extracted from Toolbar/ActionBar */
    val appBarTitle: String?,
)
