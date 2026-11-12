package com.appreveal.network

/**
 * Implement on your network client to expose traffic to AppReveal.
 */
interface NetworkObservable {
    val recentRequests: List<CapturedRequest>

    fun addObserver(observer: NetworkTrafficObserver)
}

/**
 * Receives network traffic events.
 */
interface NetworkTrafficObserver {
    fun didCapture(request: CapturedRequest)
}
