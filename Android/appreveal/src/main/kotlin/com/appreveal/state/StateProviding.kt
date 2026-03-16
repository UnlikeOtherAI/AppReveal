package com.appreveal.state

/**
 * Implement to expose app state snapshots to AppReveal.
 */
interface StateProviding {
    fun snapshot(): Map<String, Any?>
}
