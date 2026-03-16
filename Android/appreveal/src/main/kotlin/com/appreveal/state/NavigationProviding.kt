package com.appreveal.state

/**
 * Implement on your router/coordinator to expose navigation state.
 */
interface NavigationProviding {
    val currentRoute: String
    val navigationStack: List<String>
    val presentedModals: List<String>
}
